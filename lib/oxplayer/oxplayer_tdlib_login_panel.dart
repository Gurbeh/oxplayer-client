import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_dpad_text_field.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_qr_login_panel.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Phone+code(+2FA) sign-in for OXPlayer: the user's real Telegram account, authenticated
/// entirely on-device via TDLib. Once TDLib reports the account is authorized, this panel
/// automatically exchanges a Telegram-signed Mini App initData payload (see
/// OxplayerTdlibBridgeController.authenticateWithOxApi) for an OX session — no separate bot
/// approval step. Replaces the previous bot-QR-deep-link login (OxplayerTelegramLoginPanel).
///
/// TV (D-pad) uses [OxplayerDpadTextField]: visible focus ring, Select opens system IME.
///
/// TODO(l10n): strings here are hardcoded pending ARB entries; follow the oxplayerLogin* key
/// convention used elsewhere once these are ready to localize.
class OxplayerTdlibLoginPanel extends ConsumerStatefulWidget {
  const OxplayerTdlibLoginPanel({
    required this.onSuccess,
    this.showQrShortcut = true,
    this.onBackToQr,
    super.key,
  });

  final Future<void> Function() onSuccess;

  /// Phone/tablet: QR icon beside Continue. Off on TV when user already came from QR.
  final bool showQrShortcut;

  /// TV: return to QR-first panel (caller resets TDLib + flips UI).
  final Future<void> Function()? onBackToQr;

  @override
  ConsumerState<OxplayerTdlibLoginPanel> createState() => _OxplayerTdlibLoginPanelState();
}

class _OxplayerTdlibLoginPanelState extends ConsumerState<OxplayerTdlibLoginPanel> {
  final _controller = OxplayerTdlibBridgeController.instance();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _phoneFieldKey = GlobalKey<OxplayerDpadTextFieldState>();
  final _codeFieldKey = GlobalKey<OxplayerDpadTextFieldState>();
  final _passwordFieldKey = GlobalKey<OxplayerDpadTextFieldState>();
  final _submitFocus = FocusNode();
  final _eyeFocus = FocusNode();
  final _qrFocus = FocusNode();
  final _backToQrFocus = FocusNode();
  bool _busy = false;
  /// Sync gate — [setState] `_busy` alone races keyboard Done + Continue tap → double SMS.
  bool _submitLocked = false;
  bool _exchangingWithOxApi = false;
  bool _passwordVisible = false;
  /// Stay on 2FA UI if native briefly emits failed (wrong password) instead of waitingForPassword.
  bool _lockOnTwoFactor = false;
  String? _error;
  bool _oxExchangeStarted = false;
  bool _qrSheetOpen = false;
  OxTdlibAuthStateKind? _lastKind;
  /// Phone last submitted to Telegram — shown on code step + used after back.
  String? _submittedPhone;
  /// Bump when entering WaitCode so TextField remounts with a fresh input connection.
  int _codeFieldGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lastKind = _controller.state.kind;
    _controller.addListener(_onStateChanged);
    _phoneController.addListener(_onPhoneTextChanged);
    // TDLib is warmed in OxplayerLoginScreen bootstrap — focus the active auth field.
    // When QR hands off mid-2FA, kind is already waitingForPassword on first mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusAuthField(_controller.state.kind, showIme: true);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _phoneController.removeListener(_onPhoneTextChanged);
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    _eyeFocus.dispose();
    _qrFocus.dispose();
    _backToQrFocus.dispose();
    super.dispose();
  }

  void _onPhoneTextChanged() {
    if (mounted) setState(() {});
  }

  void _onSubmitPressed() {
    if (_busy || _submitLocked) return;
    final kind = _controller.state.kind;
    final onPassword = kind == OxTdlibAuthStateKind.waitingForPassword ||
        (_lockOnTwoFactor && kind == OxTdlibAuthStateKind.failed);
    final canSubmit = switch (kind) {
      OxTdlibAuthStateKind.waitingForCode => _codeController.text.trim().isNotEmpty,
      OxTdlibAuthStateKind.waitingForPassword => _passwordController.text.isNotEmpty,
      OxTdlibAuthStateKind.failed when onPassword => _passwordController.text.isNotEmpty,
      OxTdlibAuthStateKind.waitingForPhoneNumber => _phoneController.text.trim().isNotEmpty,
      _ => false,
    };
    if (!canSubmit) {
      setState(() {
        _error = onPassword
            ? 'Enter your two-factor password'
            : switch (kind) {
                OxTdlibAuthStateKind.waitingForCode => 'Enter the code from Telegram',
                _ => 'Enter a phone number with country code',
              };
      });
      return;
    }
    unawaited(_submit());
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _focusAuthField(OxTdlibAuthStateKind kind, {required bool showIme, int retry = 0}) {
    final field = switch (kind) {
      OxTdlibAuthStateKind.waitingForPhoneNumber => _phoneFieldKey.currentState,
      OxTdlibAuthStateKind.waitingForCode => _codeFieldKey.currentState,
      OxTdlibAuthStateKind.waitingForPassword => _passwordFieldKey.currentState,
      _ => null,
    };
    if (field == null) {
      final expectsField = kind == OxTdlibAuthStateKind.waitingForPhoneNumber ||
          kind == OxTdlibAuthStateKind.waitingForCode ||
          kind == OxTdlibAuthStateKind.waitingForPassword;
      if (showIme && expectsField && retry < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusAuthField(kind, showIme: showIme, retry: retry + 1);
        });
      }
      return;
    }
    // TV: ring only. Phone: EditableText + correct keyboardType (never bare TextInput.show).
    if (!showIme || AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
      field.requestFocus();
      return;
    }
    field.requestFocusAndShowIme();
  }

  /// Close previous IME, then open the correct keyboard for the new auth step.
  /// Phone → code and code → 2FA must dismiss first or Android keeps the wrong pad.
  /// QR → 2FA handoff must NOT dismiss first (nothing to reset; dismiss fights IME open).
  void _syncKeyboardForAuthStep({
    required OxTdlibAuthStateKind? from,
    required OxTdlibAuthStateKind to,
  }) {
    if (from == to) return;
    final needsImeReset = (from == OxTdlibAuthStateKind.waitingForPhoneNumber &&
            to == OxTdlibAuthStateKind.waitingForCode) ||
        (from == OxTdlibAuthStateKind.waitingForCode &&
            to == OxTdlibAuthStateKind.waitingForPassword);
    if (needsImeReset) {
      _dismissKeyboard();
    }
    // Android needs a beat after hide before a different keyboardType can attach.
    final delayMs = needsImeReset ? 400 : 80;
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _focusAuthField(to, showIme: true);
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    final kind = _controller.state.kind;
    final prev = _lastKind;
    _lastKind = kind;
    if (kind == OxTdlibAuthStateKind.waitingForPassword) {
      _lockOnTwoFactor = true;
    } else if (kind == OxTdlibAuthStateKind.ready ||
        kind == OxTdlibAuthStateKind.waitingForPhoneNumber ||
        kind == OxTdlibAuthStateKind.waitingForCode ||
        kind == OxTdlibAuthStateKind.waitingForQrConfirmation) {
      _lockOnTwoFactor = false;
    }
    // Drop spinner as soon as TDLib advances (WaitCode can arrive before RPC Ok returns —
    // otherwise Continue stays spinning through slow Telegram DC handshakes).
    final advancedPastSubmit = prev != kind &&
        (kind == OxTdlibAuthStateKind.waitingForCode ||
            kind == OxTdlibAuthStateKind.waitingForPassword ||
            kind == OxTdlibAuthStateKind.ready);
    setState(() {
      if (advancedPastSubmit) {
        _busy = false;
        // WaitCode can arrive before submitPhoneNumber's finally — unlock so the
        // code field is enabled and can take focus + numeric IME.
        _submitLocked = false;
        if (kind == OxTdlibAuthStateKind.waitingForCode &&
            prev == OxTdlibAuthStateKind.waitingForPhoneNumber) {
          _codeFieldGeneration++;
          _codeController.clear();
        }
        // Late success after a timeout error — clear stale message.
        // Keep error when re-entering waitingForPassword after a wrong-password attempt.
        if (kind != OxTdlibAuthStateKind.waitingForPassword || prev != kind) {
          _error = null;
        }
      }
    });
    if (prev != kind) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncKeyboardForAuthStep(from: prev, to: kind);
      });
    }
    if (kind == OxTdlibAuthStateKind.ready && !_oxExchangeStarted) {
      _dismissKeyboard();
      _oxExchangeStarted = true;
      unawaited(_exchangeWithOxApi());
    }
  }

  Future<void> _exchangeWithOxApi() async {
    setState(() {
      _exchangingWithOxApi = true;
      _error = null;
    });
    try {
      final result = await _controller.authenticateWithOxApi();
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(ref, result);
      if (response?.body == null) {
        throw StateError('Sign-in did not complete');
      }
      await widget.onSuccess();
    } catch (e) {
      _oxExchangeStarted = false;
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _exchangingWithOxApi = false);
    }
  }

  Future<void> _submit() async {
    if (_submitLocked || _busy) return;
    _submitLocked = true;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kind = _controller.state.kind;
      final onPassword = kind == OxTdlibAuthStateKind.waitingForPassword ||
          (_lockOnTwoFactor && kind == OxTdlibAuthStateKind.failed);
      if (onPassword) {
        if (_passwordController.text.isEmpty) {
          throw OxplayerTdlibBridgeException('Enter your two-factor password');
        }
        _dismissKeyboard();
        await _controller.submitTwoFactorPassword(_passwordController.text);
      } else {
        switch (kind) {
          case OxTdlibAuthStateKind.waitingForCode:
            final code = _codeController.text.trim();
            if (code.isEmpty) {
              throw OxplayerTdlibBridgeException('Enter the code from Telegram');
            }
            // Dismiss numeric pad immediately — next step may be text 2FA password.
            _dismissKeyboard();
            await _controller.submitCode(code);
            break;
          case OxTdlibAuthStateKind.waitingForQrConfirmation:
            setState(() => _error = 'Finish QR sign-in, or cancel it first.');
            break;
          case OxTdlibAuthStateKind.waitingForPhoneNumber:
            // Dismiss before RPC — Android keeps IME open if focus moves later without hide.
            _dismissKeyboard();
            final phone = _phoneController.text.trim();
            _submittedPhone = phone;
            await _controller.submitPhoneNumber(phone);
            break;
          default:
            throw OxplayerTdlibBridgeException(
              'Unexpected login state (${kind.name}). Use Retry on the login screen.',
            );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      _submitLocked = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backToPhoneNumber() async {
    if (_busy || _submitLocked) return;
    _dismissKeyboard();
    setState(() {
      _busy = true;
      _error = null;
      _codeController.clear();
      _passwordController.clear();
      _lockOnTwoFactor = false;
    });
    try {
      await _controller.resetForPhoneLogin();
      if (!mounted) return;
      // Prefer previously typed number so user can edit instead of retyping.
      if (_submittedPhone != null && _submittedPhone!.isNotEmpty) {
        _phoneController.text = _submittedPhone!;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusAuthField(OxTdlibAuthStateKind.waitingForPhoneNumber, showIme: true);
      });
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelQrAndReturnToPhone() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.resetForPhoneLogin();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusAuthField(OxTdlibAuthStateKind.waitingForPhoneNumber, showIme: true);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openQrSheet() async {
    if (_qrSheetOpen || _busy || _submitLocked) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _controller.ensureConfigured();
      final kind = _controller.state.kind;
      if (kind != OxTdlibAuthStateKind.waitingForPhoneNumber &&
          kind != OxTdlibAuthStateKind.uninitialized &&
          kind != OxTdlibAuthStateKind.waitingForQrConfirmation) {
        await _controller.resetForPhoneLogin();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = oxTdlibAuthUserMessage(e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    _qrSheetOpen = true;
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rootContext.mounted) {
        _qrSheetOpen = false;
        return;
      }
      showModalBottomSheet<void>(
        context: rootContext,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          final bottom = MediaQuery.paddingOf(sheetContext).bottom;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bottom),
              child: OxplayerTdlibQrLoginPanel(
                onSuccess: () async {
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  await widget.onSuccess();
                },
                onNeedTwoFactorPassword: () {
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ),
          );
        },
      ).whenComplete(() async {
        _qrSheetOpen = false;
        if (!mounted) return;
        final kind = _controller.state.kind;
        // Only skip reset when already back on a phone-auth step (or signed in).
        if (kind == OxTdlibAuthStateKind.ready ||
            kind == OxTdlibAuthStateKind.waitingForPhoneNumber ||
            kind == OxTdlibAuthStateKind.waitingForCode ||
            kind == OxTdlibAuthStateKind.waitingForPassword) {
          if (mounted) {
            setState(() {});
            if (kind == OxTdlibAuthStateKind.waitingForPassword) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _syncKeyboardForAuthStep(
                  from: OxTdlibAuthStateKind.waitingForQrConfirmation,
                  to: OxTdlibAuthStateKind.waitingForPassword,
                );
              });
            }
          }
          return;
        }
        await _cancelQrAndReturnToPhone();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _controller.state.kind;

    // Show QR icon whenever the phone-number Continue row is visible — not only for
    // waitingForPhoneNumber (after QR abort/reset kind can briefly be closed/failed/uninitialized).
    final showPasswordStep = kind == OxTdlibAuthStateKind.waitingForPassword ||
        (_lockOnTwoFactor && kind == OxTdlibAuthStateKind.failed);
    final onPhoneContinueStep = switch (kind) {
      OxTdlibAuthStateKind.waitingForCode ||
      OxTdlibAuthStateKind.waitingForPassword ||
      OxTdlibAuthStateKind.ready =>
        false,
      OxTdlibAuthStateKind.failed when _lockOnTwoFactor => false,
      OxTdlibAuthStateKind.waitingForQrConfirmation => _qrSheetOpen,
      _ => true,
    };
    final showQrOption = widget.showQrShortcut && onPhoneContinueStep;
    final showBackToQr = widget.onBackToQr != null && onPhoneContinueStep;
    final showBackToPhone = showPasswordStep || kind == OxTdlibAuthStateKind.waitingForCode;

    if (kind == OxTdlibAuthStateKind.waitingForQrConfirmation && !_qrSheetOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('QR sign-in in progress', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Open the QR sheet to scan, or cancel to enter a phone number.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            focusNode: _submitFocus,
            autofocus: true,
            style: FilledButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : _openQrSheet,
            child: const Text('Show QR code'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            focusNode: _backToQrFocus,
            style: OutlinedButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _busy ? null : _cancelQrAndReturnToPhone,
            child: const Text('Use phone number instead'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      );
    }

    late final Widget field;
    late final String buttonLabel;
    final effectiveKind =
        showPasswordStep ? OxTdlibAuthStateKind.waitingForPassword : kind;
    switch (effectiveKind) {
      case OxTdlibAuthStateKind.waitingForCode:
        final phoneLabel = (_submittedPhone?.trim().isNotEmpty ?? false)
            ? _submittedPhone!.trim()
            : (_phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : 'your number');
        field = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A login code was sent to $phoneLabel in Telegram. Enter the code from your Telegram account.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: ValueKey('tdlib-auth-code-$_codeFieldGeneration'),
              child: OxplayerDpadTextField(
                key: _codeFieldKey,
                controller: _codeController,
                focusNode: _codeFocus,
                label: 'Code',
                hint: '• • • • •',
                // Phone dialpad on Android/Gboard (TextInputType.number often opens QWERTY+row).
                // digitsOnly still strips non-digits.
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.center,
                autofocus: false,
                enabled: !_busy && !_submitLocked,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(5),
                ],
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                onChanged: (value) {
                  setState(() {});
                  // Telegram login codes are 5 digits — submit as soon as it's complete.
                  if (value.trim().length == 5 && !_submitLocked && !_busy) {
                    _dismissKeyboard();
                    unawaited(_submit());
                  }
                },
                onKeyboardClosed: () {
                  if (_codeController.text.trim().isNotEmpty && !_submitLocked && !_busy) {
                    _dismissKeyboard();
                    unawaited(_submit());
                  }
                },
                onMoveFocusDown: () => _submitFocus.requestFocus(),
              ),
            ),
          ],
        );
        buttonLabel = 'Confirm code';
        break;
      case OxTdlibAuthStateKind.waitingForPassword:
        final hint = _controller.state.passwordHint;
        final fieldsEnabled = !_busy && !_submitLocked;
        field = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: OxplayerDpadTextField(
                key: _passwordFieldKey,
                controller: _passwordController,
                focusNode: _passwordFocus,
                label: 'Two-factor password',
                hint: (hint != null && hint.isNotEmpty) ? hint : null,
                obscureText: !_passwordVisible,
                keyboardType: TextInputType.visiblePassword,
                autofocus: false,
                enabled: fieldsEnabled,
                onChanged: (_) => setState(() {}),
                onKeyboardClosed: () {
                  if (_passwordController.text.isNotEmpty && !_submitLocked && !_busy) {
                    _submitFocus.requestFocus();
                  }
                },
                onMoveFocusDown: () => _eyeFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              height: 52,
              child: IconButton.outlined(
                focusNode: _eyeFocus,
                tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                style: IconButton.styleFrom(shape: FladderTheme.largeShape).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: theme.colorScheme.primary, width: 3);
                    }
                    return BorderSide(color: theme.colorScheme.outline);
                  }),
                ),
                onPressed: fieldsEnabled
                    ? () => setState(() => _passwordVisible = !_passwordVisible)
                    : null,
                icon: Icon(
                  _passwordVisible ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
                ),
              ),
            ),
          ],
        );
        buttonLabel = 'Confirm password';
        break;
      case OxTdlibAuthStateKind.ready:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(IconsaxPlusBold.tick_circle, size: 48, color: theme.colorScheme.primary),
              if (_exchangingWithOxApi) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    _oxExchangeStarted = true;
                    unawaited(_exchangeWithOxApi());
                  },
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        );
      default:
        field = OxplayerDpadTextField(
          key: _phoneFieldKey,
          controller: _phoneController,
          focusNode: _phoneFocus,
          label: 'Phone number',
          hint: '+1 234 567 8900',
          keyboardType: TextInputType.phone,
          autofocus: true,
          enabled: !_busy && !_submitLocked,
          autofillHints: const [AutofillHints.telephoneNumber],
          onChanged: (_) => setState(() {}),
          onKeyboardClosed: () {
            // Enter/Done: dismiss IME + submit so WaitCode can autofocus code field.
            if (_phoneController.text.trim().isNotEmpty && !_submitLocked && !_busy) {
              unawaited(_submit());
            }
          },
          onMoveFocusDown: () => _submitFocus.requestFocus(),
        );
        buttonLabel = 'Continue';
    }

    final sendingPhone = _busy && kind == OxTdlibAuthStateKind.waitingForPhoneNumber;
    // Keep buttons focusable for D-pad even when the field is empty — null onPressed
    // removes the node from the focus tree and traps the remote on the TextField.
    final actionsEnabled = !_busy && !_submitLocked;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sign in with Telegram',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Log into your Telegram account to use OXPlayer.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: field,
          ),
          if (sendingPhone) ...[
            const SizedBox(height: 12),
            Text(
              'Contacting Telegram…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: FilledButton(
                    focusNode: _submitFocus,
                    style: FilledButton.styleFrom(
                      shape: FladderTheme.largeShape,
                      minimumSize: const Size.fromHeight(52),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) {
                          return BorderSide(
                            color: theme.colorScheme.secondary,
                            width: 3,
                          );
                        }
                        return BorderSide.none;
                      }),
                      elevation: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.focused)) return 6;
                        return 0;
                      }),
                    ),
                    onPressed: actionsEnabled ? _onSubmitPressed : null,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(buttonLabel),
                  ),
                ),
              ),
              if (showQrOption) ...[
                const SizedBox(width: 10),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(3),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: IconButton.outlined(
                      focusNode: _qrFocus,
                      tooltip: 'Sign in with QR code',
                      style: IconButton.styleFrom(shape: FladderTheme.largeShape),
                      onPressed: actionsEnabled ? _openQrSheet : null,
                      icon: const Icon(IconsaxPlusLinear.scan_barcode),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showBackToPhone) ...[
            const SizedBox(height: 10),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3.5),
              child: TextButton.icon(
                onPressed: actionsEnabled ? () => unawaited(_backToPhoneNumber()) : null,
                icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
                label: const Text('Change phone number'),
              ),
            ),
          ],
          if (showBackToQr) ...[
            const SizedBox(height: 10),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: OutlinedButton.icon(
                focusNode: _backToQrFocus,
                style: OutlinedButton.styleFrom(
                  shape: FladderTheme.largeShape,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: actionsEnabled
                    ? () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onBackToQr!();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      }
                    : null,
                icon: const Icon(IconsaxPlusLinear.scan_barcode),
                label: const Text('Back to QR code'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
