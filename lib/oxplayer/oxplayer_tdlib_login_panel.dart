import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_qr_login_panel.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/theme.dart';

/// Phone+code(+2FA) sign-in for OXPlayer: the user's real Telegram account, authenticated
/// entirely on-device via TDLib. Once TDLib reports the account is authorized, this panel
/// automatically exchanges a Telegram-signed Mini App initData payload (see
/// OxplayerTdlibBridgeController.authenticateWithOxApi) for an OX session — no separate bot
/// approval step. Replaces the previous bot-QR-deep-link login (OxplayerTelegramLoginPanel).
///
/// Uses Material [TextField] (not Fladder [OutlinedTextField]) so phone entry stays editable on
/// emulators — OutlinedTextField becomes readOnly when InputDevice.dPad + useSystemIME=false.
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
  final _submitFocus = FocusNode();
  final _qrFocus = FocusNode();
  final _backToQrFocus = FocusNode();
  final _togglePasswordFocus = FocusNode();
  bool _busy = false;
  /// Sync gate — [setState] `_busy` alone races keyboard Done + Continue tap → double SMS.
  bool _submitLocked = false;
  bool _exchangingWithOxApi = false;
  bool _passwordVisible = false;
  String? _error;
  bool _oxExchangeStarted = false;
  bool _qrSheetOpen = false;
  OxTdlibAuthStateKind? _lastKind;

  @override
  void initState() {
    super.initState();
    _lastKind = _controller.state.kind;
    _controller.addListener(_onStateChanged);
    _phoneController.addListener(_onPhoneTextChanged);
    // D-pad: arrow keys on TextField move the caret by default — steal Down so TV
    // remotes can reach Continue / QR instead of trapping focus in the field.
    _phoneFocus.onKeyEvent = _onFieldKeyEvent;
    _codeFocus.onKeyEvent = _onFieldKeyEvent;
    _passwordFocus.onKeyEvent = _onFieldKeyEvent;
    // TDLib is warmed in OxplayerLoginScreen bootstrap — just focus the field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.state.kind == OxTdlibAuthStateKind.waitingForPhoneNumber) {
        _phoneFocus.requestFocus();
      }
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
    _qrFocus.dispose();
    _backToQrFocus.dispose();
    _togglePasswordFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_submitFocus.canRequestFocus) {
        _submitFocus.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onPhoneTextChanged() {
    if (mounted) setState(() {});
  }

  void _onSubmitPressed() {
    if (_busy || _submitLocked) return;
    final kind = _controller.state.kind;
    final canSubmit = switch (kind) {
      OxTdlibAuthStateKind.waitingForCode => _codeController.text.trim().isNotEmpty,
      OxTdlibAuthStateKind.waitingForPassword => _passwordController.text.isNotEmpty,
      OxTdlibAuthStateKind.waitingForPhoneNumber => _phoneController.text.trim().isNotEmpty,
      _ => false,
    };
    if (!canSubmit) {
      setState(() {
        _error = switch (kind) {
          OxTdlibAuthStateKind.waitingForCode => 'Enter the code from Telegram',
          OxTdlibAuthStateKind.waitingForPassword => 'Enter your two-factor password',
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

  /// Close previous IME, then open the correct keyboard for the new auth step.
  /// Numeric code → text 2FA must dismiss first or Android keeps the number pad.
  void _syncKeyboardForAuthStep({
    required OxTdlibAuthStateKind? from,
    required OxTdlibAuthStateKind to,
  }) {
    if (from == to) return;
    _dismissKeyboard();
    // Let the numeric IME fully tear down before requesting text focus.
    final delayMs = (from == OxTdlibAuthStateKind.waitingForCode &&
            to == OxTdlibAuthStateKind.waitingForPassword)
        ? 200
        : 80;
    Future<void>.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      switch (to) {
        case OxTdlibAuthStateKind.waitingForPhoneNumber:
          _phoneFocus.requestFocus();
        case OxTdlibAuthStateKind.waitingForCode:
          _codeFocus.requestFocus();
        case OxTdlibAuthStateKind.waitingForPassword:
          _passwordFocus.requestFocus();
        default:
          break;
      }
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    final kind = _controller.state.kind;
    final prev = _lastKind;
    _lastKind = kind;
    // Drop spinner as soon as TDLib advances (WaitCode can arrive before RPC Ok returns —
    // otherwise Continue stays spinning through slow Telegram DC handshakes).
    final advancedPastSubmit = prev != kind &&
        (kind == OxTdlibAuthStateKind.waitingForCode ||
            kind == OxTdlibAuthStateKind.waitingForPassword ||
            kind == OxTdlibAuthStateKind.ready);
    setState(() {
      if (advancedPastSubmit) {
        _busy = false;
        // Late success after a timeout error — clear stale message.
        _error = null;
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
      switch (_controller.state.kind) {
        case OxTdlibAuthStateKind.waitingForCode:
          final code = _codeController.text.trim();
          if (code.isEmpty) {
            throw OxplayerTdlibBridgeException('Enter the code from Telegram');
          }
          // Dismiss numeric pad immediately — next step may be text 2FA password.
          _dismissKeyboard();
          await _controller.submitCode(code);
          break;
        case OxTdlibAuthStateKind.waitingForPassword:
          if (_passwordController.text.isEmpty) {
            throw OxplayerTdlibBridgeException('Enter your two-factor password');
          }
          _dismissKeyboard();
          await _controller.submitTwoFactorPassword(_passwordController.text);
          break;
        case OxTdlibAuthStateKind.waitingForQrConfirmation:
          setState(() => _error = 'Finish QR sign-in, or cancel it first.');
          break;
        case OxTdlibAuthStateKind.waitingForPhoneNumber:
          await _controller.submitPhoneNumber(_phoneController.text);
          _dismissKeyboard();
          break;
        default:
          throw OxplayerTdlibBridgeException(
            'Unexpected login state (${_controller.state.kind.name}). Use Retry on the login screen.',
          );
      }
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      _submitLocked = false;
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
      if (mounted) _phoneFocus.requestFocus();
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

  InputDecoration _fieldDecoration(ThemeData theme, {required String label, String? hint}) {
    final radius = BorderRadius.circular(8);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(borderRadius: radius),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _controller.state.kind;

    // Show QR icon whenever the phone-number Continue row is visible — not only for
    // waitingForPhoneNumber (after QR abort/reset kind can briefly be closed/failed/uninitialized).
    final onPhoneContinueStep = switch (kind) {
      OxTdlibAuthStateKind.waitingForCode ||
      OxTdlibAuthStateKind.waitingForPassword ||
      OxTdlibAuthStateKind.ready =>
        false,
      OxTdlibAuthStateKind.waitingForQrConfirmation => _qrSheetOpen,
      _ => true,
    };
    final showQrOption = widget.showQrShortcut && onPhoneContinueStep;
    final showBackToQr = widget.onBackToQr != null && onPhoneContinueStep;
    final canSubmitPhone = kind == OxTdlibAuthStateKind.waitingForPhoneNumber &&
        _phoneController.text.trim().isNotEmpty;

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
    switch (kind) {
      case OxTdlibAuthStateKind.waitingForCode:
        field = TextField(
          key: const ValueKey('tdlib-auth-code'),
          controller: _codeController,
          focusNode: _codeFocus,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: _fieldDecoration(theme, label: 'Code', hint: '• • • • •'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (!_submitLocked && !_busy) unawaited(_submit());
          },
        );
        buttonLabel = 'Confirm code';
        break;
      case OxTdlibAuthStateKind.waitingForPassword:
        final hint = _controller.state.passwordHint;
        field = TextField(
          key: const ValueKey('tdlib-auth-password'),
          controller: _passwordController,
          focusNode: _passwordFocus,
          obscureText: !_passwordVisible,
          // Text keyboard (not number pad) for 2FA cloud password.
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autofocus: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: _fieldDecoration(
            theme,
            label: 'Two-factor password',
            hint: (hint != null && hint.isNotEmpty) ? hint : null,
          ).copyWith(
            suffixIcon: IconButton(
              focusNode: _togglePasswordFocus,
              tooltip: _passwordVisible ? 'Hide password' : 'Show password',
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(
                _passwordVisible ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
              ),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (!_submitLocked && !_busy) unawaited(_submit());
          },
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
        field = TextField(
          controller: _phoneController,
          focusNode: _phoneFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofocus: true,
          autofillHints: const [AutofillHints.telephoneNumber],
          enableSuggestions: false,
          decoration: _fieldDecoration(
            theme,
            label: 'Phone number',
            hint: '+1 234 567 8900',
          ),
          onSubmitted: (_) {
            if (!_submitLocked && !_busy && canSubmitPhone) unawaited(_submit());
          },
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
