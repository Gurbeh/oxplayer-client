import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_connecting_notice.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/theme.dart';

/// Telegram QR login token lifetime is ~30s (TDLib `auth.loginToken.expires`).
/// Countdown is display-only — gotd refreshes tokens itself and pushes a new URL via
/// auth state. Do NOT call [OxplayerTdlibBridgeController.requestQrLogin] on expiry:
/// that cancels the in-flight QR.Auth goroutine and races phone scans into
/// AuthLoginTokenMigrateTo failures.
const _kQrRefreshInterval = Duration(seconds: 30);

/// Android TV sign-in for OXPlayer: QR-first (remote typing is bad UX). Optional
/// [onUsePhoneNumber] lets the user focus a button and switch to the phone panel.
/// When [onNeedTwoFactorPassword] is set, 2FA is handed off to that callback (close QR
/// sheet / switch to phone panel) instead of showing the password field inline.
///
/// TODO(l10n): strings here are hardcoded pending ARB entries; follow the oxplayerLogin* key
/// convention used elsewhere once these are ready to localize.
class OxplayerTdlibQrLoginPanel extends ConsumerStatefulWidget {
  const OxplayerTdlibQrLoginPanel({
    required this.onSuccess,
    this.onUsePhoneNumber,
    this.onNeedTwoFactorPassword,
    super.key,
  });

  final Future<void> Function() onSuccess;

  /// TV: focused with D-pad — switches to phone-number panel.
  final Future<void> Function()? onUsePhoneNumber;

  /// Phone QR sheet / TV: leave QR UI so the phone login panel can show 2FA.
  final VoidCallback? onNeedTwoFactorPassword;

  @override
  ConsumerState<OxplayerTdlibQrLoginPanel> createState() => _OxplayerTdlibQrLoginPanelState();
}

class _OxplayerTdlibQrLoginPanelState extends ConsumerState<OxplayerTdlibQrLoginPanel> {
  final _controller = OxplayerTdlibBridgeController.instance();
  final _passwordController = TextEditingController();
  final _phoneOptionFocus = FocusNode();
  bool _oxExchangeStarted = false;
  bool _exchangingWithOxApi = false;
  bool _passwordBusy = false;
  bool _passwordVisible = false;
  bool _twoFactorHandedOff = false;
  bool _starting = false;
  bool _refreshingQr = false;
  bool _scanConfirming = false;
  String? _error;
  String? _shownQrUrl;
  Timer? _urlWaitTimer;
  Timer? _expiryTimer;
  Timer? _countdownTicker;
  Timer? _confirmWatchdog;
  int _qrRetryCount = 0;
  DateTime? _qrIssuedAt;
  int _secondsUntilRefresh = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A leftover-but-valid `ready` Telegram session can already be the state at mount now
      // (prepareForLoginScreen no longer force-resets one away — see its doc), in which case
      // _start()'s QR request is moot and _onStateChanged's ready/exchange handling — normally
      // only reached via a FUTURE transition its listener observes — needs a first, manual kick
      // for a transition that already happened before this panel existed to listen for it.
      if (_controller.state.kind == OxTdlibAuthStateKind.ready) {
        _onStateChanged();
        return;
      }
      _start();
    });
  }

  @override
  void dispose() {
    _urlWaitTimer?.cancel();
    _expiryTimer?.cancel();
    _countdownTicker?.cancel();
    _confirmWatchdog?.cancel();
    _controller.removeListener(_onStateChanged);
    _passwordController.dispose();
    _phoneOptionFocus.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[ox-tdlib-auth] qr-panel: $message');
    }
  }

  void _armUrlWaitTimer() {
    _urlWaitTimer?.cancel();
    _urlWaitTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      final url = _controller.state.qrLoginUrl;
      final kind = _controller.state.kind;
      if (url != null && url.isNotEmpty) return;
      _log('QR URL still missing after 8s (kind=$kind) — retry #${_qrRetryCount + 1}');
      if (_qrRetryCount >= 3) {
        setState(() {
          _error =
              'QR code did not arrive from Telegram (state=$kind). Check network / try again.';
        });
        return;
      }
      _qrRetryCount++;
      unawaited(_requestQr());
    });
  }

  void _armExpiryRefresh() {
    _expiryTimer?.cancel();
    _countdownTicker?.cancel();
    _qrIssuedAt = DateTime.now();
    _secondsUntilRefresh = _kQrRefreshInterval.inSeconds;
    // Display-only countdown. gotd re-exports when the token expires and emits a new
    // waitingForQrConfirmation URL — we re-arm from _onStateChanged. No requestQrLogin.
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _qrIssuedAt == null) return;
      final left = _kQrRefreshInterval.inSeconds -
          DateTime.now().difference(_qrIssuedAt!).inSeconds;
      final clamped = left.clamp(0, _kQrRefreshInterval.inSeconds);
      setState(() {
        _secondsUntilRefresh = clamped;
        // At 0 show "Refreshing…" until gotd pushes the next URL (re-arms above).
        _refreshingQr = clamped == 0;
      });
    });
  }

  Future<void> _requestQr() async {
    try {
      await _controller.requestQrLogin();
      _armUrlWaitTimer();
    } catch (e) {
      _log('requestQrLogin failed: $e');
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      await _controller.ensureConfigured();
      final existing = _controller.state.qrLoginUrl;
      if (existing != null && existing.isNotEmpty) {
        _log('already have qrLoginUrl (${existing.length}c)');
        _shownQrUrl = existing;
        _urlWaitTimer?.cancel();
        _armExpiryRefresh();
      } else {
        await _requestQr();
      }
    } catch (e) {
      _log('start failed: $e');
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      _starting = false;
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = _controller.state;
    final url = state.qrLoginUrl;
    _log('state=${state.kind.name} url=${url != null && url.isNotEmpty}');

    final confirming = state.kind == OxTdlibAuthStateKind.waitingForQrConfirmation &&
        (url == null || url.isEmpty);
    if (confirming && !_scanConfirming) {
      _armConfirmWatchdog();
    } else if (!confirming) {
      _confirmWatchdog?.cancel();
    }
    _scanConfirming = confirming;

    if (url != null && url.isNotEmpty) {
      _urlWaitTimer?.cancel();
      _qrRetryCount = 0;
      final notice = state.errorMessage;
      final expiredNotice = notice != null &&
          notice.toUpperCase().contains('AUTH_TOKEN');
      if (url != _shownQrUrl) {
        _shownQrUrl = url;
        _armExpiryRefresh();
        _log('QR URL updated (${url.length}c) — refresh timer armed');
        if (expiredNotice) {
          setState(() => _error = oxTdlibAuthUserMessage(notice));
          return;
        }
      } else if (expiredNotice) {
        setState(() => _error = oxTdlibAuthUserMessage(notice));
        return;
      }
    }
    setState(() {});
    if (state.kind == OxTdlibAuthStateKind.waitingForPassword &&
        widget.onNeedTwoFactorPassword != null &&
        !_twoFactorHandedOff) {
      _twoFactorHandedOff = true;
      _expiryTimer?.cancel();
      _countdownTicker?.cancel();
      _urlWaitTimer?.cancel();
      _confirmWatchdog?.cancel();
      _log('2FA required — handing off to phone login panel');
      widget.onNeedTwoFactorPassword!();
      return;
    }
    if (state.kind == OxTdlibAuthStateKind.ready && !_oxExchangeStarted) {
      _expiryTimer?.cancel();
      _countdownTicker?.cancel();
      _confirmWatchdog?.cancel();
      unawaited(_maybeStartOxExchange());
    }
    if (state.kind == OxTdlibAuthStateKind.failed) {
      final raw = state.errorMessage ?? 'Telegram auth failed';
      final friendly = oxTdlibAuthUserMessage(raw);
      final upper = raw.toUpperCase();
      if (upper.contains('AUTH_TOKEN')) {
        // Should be rare after native recovery — still unstick UI + mint new QR.
        setState(() => _error = friendly);
        unawaited(_recoverFreshQr());
        return;
      }
      setState(() => _error = friendly);
    }
  }

  void _armConfirmWatchdog() {
    _confirmWatchdog?.cancel();
    _confirmWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      final state = _controller.state;
      final url = state.qrLoginUrl;
      if (state.kind != OxTdlibAuthStateKind.waitingForQrConfirmation) return;
      if (url != null && url.isNotEmpty) return;
      _log('confirming stuck 20s — recovering fresh QR');
      setState(() => _error = 'Scan timed out. Scan the new QR code.');
      unawaited(_recoverFreshQr());
    });
  }

  Future<void> _recoverFreshQr() async {
    _confirmWatchdog?.cancel();
    try {
      final kind = _controller.state.kind;
      if (kind == OxTdlibAuthStateKind.failed ||
          kind == OxTdlibAuthStateKind.ready ||
          kind == OxTdlibAuthStateKind.closed) {
        await _controller.resetForPhoneLogin();
      }
      await _controller.requestQrLogin();
      _armUrlWaitTimer();
    } catch (e) {
      _log('recoverFreshQr failed: $e');
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    }
  }

  /// Guards the ready-triggered exchange against a restored *bot* session — see the phone-login
  /// panel's identical guard (oxplayer_tdlib_login_panel.dart) for the full explanation. A bot
  /// session landing here (this device's connected delivery bot restored instead of the real
  /// user session) was never going to complete this exchange (fetchWebAppInitData is
  /// user-account-only), so don't try and don't mark _oxExchangeStarted.
  Future<void> _maybeStartOxExchange() async {
    if (_oxExchangeStarted) return;
    if (await _controller.isNativeSessionActuallyBot()) {
      _log('ready state is a bot session, skipping exchange');
      return;
    }
    if (!mounted || _controller.state.kind != OxTdlibAuthStateKind.ready || _oxExchangeStarted) {
      return;
    }
    _oxExchangeStarted = true;
    await _exchangeWithOxApi();
  }

  Future<void> _exchangeWithOxApi() async {
    setState(() {
      _exchangingWithOxApi = true;
      _error = null;
    });
    try {
      final result = await _controller.authenticateWithOxApi();
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(
        ref,
        result,
        loginKind: OxplayerOxLoginKind.session,
      );
      if (response?.body == null) {
        throw StateError('Sign-in did not complete');
      }
      await widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _exchangingWithOxApi = false);
    }
  }

  Future<void> _submitPassword() async {
    setState(() => _passwordBusy = true);
    try {
      await _controller.submitTwoFactorPassword(_passwordController.text);
    } catch (e) {
      if (mounted) setState(() => _error = oxTdlibAuthUserMessage(e));
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _controller.state;
    final liveUrl = state.qrLoginUrl;
    final qrUrl = (liveUrl != null && liveUrl.isNotEmpty) ? liveUrl : _shownQrUrl;
    // Native emits empty QR URL while Import runs after scan — keep last QR dimmed + spinner.
    final scanConfirming = state.kind == OxTdlibAuthStateKind.waitingForQrConfirmation &&
        (liveUrl == null || liveUrl.isEmpty) &&
        (_shownQrUrl != null && _shownQrUrl!.isNotEmpty);

    if (state.kind == OxTdlibAuthStateKind.ready) {
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
                style: TextStyle(color: theme.colorScheme.error),
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
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign in with Telegram',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Open Telegram on your phone → Settings → Devices → Link Desktop Device, then scan this code.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (qrUrl != null && qrUrl.isNotEmpty) ...[
          // Hidden Play review path: hold QR / OK 5s → demo library. No on-screen hint.
          OxplayerTestAccountQrHold(
            autofocus: true,
            onHoldComplete: () {
              unawaited(oxplayerSignInAsTestAccount(
                ref: ref,
                context: context,
                onSuccess: widget.onSuccess,
              ));
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (_refreshingQr || scanConfirming) ? 0.45 : 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: QrImageView(
                      data: qrUrl,
                      size: 240,
                      version: QrVersions.auto,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                if (_refreshingQr || scanConfirming) const CircularProgressIndicator(),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            scanConfirming
                ? 'Confirming on Telegram…'
                : _refreshingQr
                    ? 'Refreshing code…'
                    : 'Code refreshes in ${_secondsUntilRefresh}s',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ] else if (_error == null)
          // No QR yet means the MTProto connection is still coming up. This used to be a bare
          // spinner, which on a slow network sat silent long enough to look hung.
          const OxplayerTelegramConnectingNotice(),
        // Inline 2FA only when no hand-off callback (phone sheet / TV switch to LoginPanel).
        if (state.kind == OxTdlibAuthStateKind.waitingForPassword &&
            widget.onNeedTwoFactorPassword == null) ...[
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Two-factor password',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                      icon: Icon(
                        _passwordVisible ? IconsaxPlusLinear.eye_slash : IconsaxPlusLinear.eye,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitPassword(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 52,
                child: IconButton.filled(
                  style: IconButton.styleFrom(shape: FladderTheme.largeShape),
                  onPressed: _passwordBusy ? null : _submitPassword,
                  icon: _passwordBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(IconsaxPlusLinear.arrow_right_3),
                ),
              ),
            ],
          ),
        ],
          if (widget.onUsePhoneNumber != null &&
            state.kind != OxTdlibAuthStateKind.waitingForPassword) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            focusNode: _phoneOptionFocus,
            autofocus: true,
            style: OutlinedButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              _expiryTimer?.cancel();
              _countdownTicker?.cancel();
              await widget.onUsePhoneNumber!();
            },
            icon: const Icon(IconsaxPlusLinear.call),
            label: const Text('Sign in with phone number'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _qrRetryCount = 0;
              setState(() => _error = null);
              unawaited(_recoverFreshQr());
            },
            child: const Text('Get new QR'),
          ),
        ],
      ],
    );
  }
}
