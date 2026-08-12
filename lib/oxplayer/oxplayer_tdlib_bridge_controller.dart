import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart' show OxplayerLoginAttemptPollResult;
import 'package:fladder/oxplayer/oxplayer_tdlib_session_cache.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_webapp_auth_api.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_windows_bridge_stub.dart'
    if (dart.library.io) 'package:fladder/oxplayer/oxplayer_telegram_windows_bridge.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

const _kOxTdlibDeviceIdPrefsKey = 'oxplayer_td_device_id';
const _kTdlibAuthLogTag = 'ox-tdlib-auth';

class OxplayerTdlibBridgeException implements Exception {
  OxplayerTdlibBridgeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Short user-facing auth errors — never [PlatformException.toString] (includes stacktrace).
String oxTdlibAuthUserMessage(Object error) {
  final raw = switch (error) {
    OxplayerTdlibBridgeException e => e.message,
    PlatformException e => (e.message?.trim().isNotEmpty == true) ? e.message!.trim() : e.code,
    _ => error.toString(),
  };
  final upper = raw.toUpperCase();
  if (upper.contains('PHONE_CODE_INVALID') || upper.contains('PHONE_CODE_EMPTY')) {
    return 'Wrong code. Try again.';
  }
  if (upper.contains('PHONE_CODE_EXPIRED')) {
    return 'Code expired. Go back and request a new one.';
  }
  if (upper.contains('PHONE_NUMBER_INVALID') || upper.contains('PHONE_NUMBER_FLOOD')) {
    return upper.contains('FLOOD')
        ? 'Too many attempts. Wait a bit, then try again.'
        : 'Invalid phone number. Include country code (e.g. +98…).';
  }
  if (upper.contains('AUTH_TOKEN_EXPIRED') || upper.contains('AUTH_TOKEN_INVALID')) {
    return 'That QR code expired. Scan the new one.';
  }
  if (upper.contains('PASSWORD_HASH_INVALID') ||
      upper.contains('PASSWORD_EMPTY') ||
      upper.contains('INVALID PASSWORD')) {
    return 'Wrong two-factor password.';
  }
  if (upper.contains('FLOOD_WAIT') || upper.contains('TOO_MANY_REQUESTS')) {
    return 'Too many attempts. Wait a bit, then try again.';
  }
  if (upper.contains('NETWORK') ||
      upper.contains('TIMEOUT') ||
      upper.contains('TIMED OUT') ||
      upper.contains('CONNECTION') ||
      upper.contains('COULD NOT REACH TELEGRAM')) {
    return 'Could not reach Telegram. Check internet / VPN and try again.';
  }
  // Strip PlatformException / TdlibException wrappers if any slipped through.
  final cleaned = raw
      .replaceFirst(RegExp(r'^PlatformException\([^,]*,\s*'), '')
      .replaceFirst(RegExp(r'^TdlibException:\s*'), '')
      .split(',')
      .first
      .trim();
  if (cleaned.length > 140) {
    return '${cleaned.substring(0, 140)}…';
  }
  return cleaned.isEmpty ? 'Something went wrong. Try again.' : cleaned;
}

/// Thin controller wrapping OxTdlibBridgeApi (Android Pigeon) or Windows gotd FFI host.
/// One instance per app process.
class OxplayerTdlibBridgeController extends ChangeNotifier implements OxTdlibBridgeEvents {
  OxplayerTdlibBridgeController._() {
    if (!oxTelegramUseWindowsHost()) {
      OxTdlibBridgeEvents.setUp(this);
    }
    if (oxTelegramUseWindowsHost()) {
      _windows = OxTelegramWindowsBridge(onAuthStateChanged: onAuthStateChanged);
    }
  }

  static OxplayerTdlibBridgeController? _instance;

  factory OxplayerTdlibBridgeController.instance() {
    return _instance ??= OxplayerTdlibBridgeController._();
  }

  final _api = OxTdlibBridgeApi();
  OxTelegramWindowsBridge? _windows;
  OxTdlibAuthState _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
  bool _configured = false;

  bool get _useWindows => _windows != null;

  OxTdlibAuthState get state => _state;

  /// True once TDLib finished setTdlibParameters and is ready for phone/QR/code/password.
  bool get isReadyForAuthInput => _isInteractiveAuthKind(_state.kind);

  static bool _isInteractiveAuthKind(OxTdlibAuthStateKind kind) {
    switch (kind) {
      case OxTdlibAuthStateKind.waitingForPhoneNumber:
      case OxTdlibAuthStateKind.waitingForCode:
      case OxTdlibAuthStateKind.waitingForPassword:
      case OxTdlibAuthStateKind.waitingForQrConfirmation:
      case OxTdlibAuthStateKind.ready:
      case OxTdlibAuthStateKind.failed:
        return true;
      case OxTdlibAuthStateKind.uninitialized:
      case OxTdlibAuthStateKind.loggingOut:
      case OxTdlibAuthStateKind.closed:
        return false;
    }
  }

  void _log(String message) {
    developer.log(message, name: _kTdlibAuthLogTag);
    if (kDebugMode) {
      debugPrint('[$_kTdlibAuthLogTag] $message');
    }
  }

  @override
  void onAuthStateChanged(OxTdlibAuthState state) {
    _log(
      'state → ${state.kind.name}'
      '${state.qrLoginUrl != null ? ' qrUrl=${state.qrLoginUrl!.length}c' : ''}'
      '${state.errorMessage != null ? ' err=${state.errorMessage}' : ''}',
    );
    _state = state;
    if (state.kind == OxTdlibAuthStateKind.uninitialized ||
        state.kind == OxTdlibAuthStateKind.closed) {
      _configured = false;
    }
    notifyListeners();
  }

  /// Idempotent — safe to call from every login panel's initState.
  /// Waits until TDLib accepts phone/QR input (past setTdlibParameters).
  Future<void> ensureConfigured({
    Duration readyTimeout = const Duration(seconds: 45),
  }) async {
    if (_configured) {
      // Don't trust the cached flag alone — re-verify against native's actual current state.
      // Observed in practice: _configured stays true (this singleton survives Dart hot restarts)
      // while native's auth state regresses to uninitialized, with nothing left to call
      // configure() again and drive it forward — waitUntilReadyForAuthInput then polls a dead
      // state for the full timeout instead of failing fast or self-healing.
      final polled = _useWindows ? _windows!.currentAuthState() : await _api.currentAuthState();
      if (polled.kind != OxTdlibAuthStateKind.uninitialized) {
        _state = polled;
        _log('ensureConfigured: already configured kind=${_state.kind.name}');
        await waitUntilReadyForAuthInput(timeout: readyTimeout);
        return;
      }
      _log('ensureConfigured: cached configured=true but native reports uninitialized — reconfiguring');
      _configured = false;
    }
    final apiId = OxplayerEnv.telegramApiId;
    final apiHash = OxplayerEnv.telegramApiHash;
    if (apiId == null || apiHash == null) {
      throw OxplayerTdlibBridgeException(
        'TELEGRAM_API_ID/TELEGRAM_API_HASH not configured for this build',
      );
    }
    _log('ensureConfigured: calling native configure apiId=$apiId');
    if (_useWindows) {
      await _windows!.configure(apiId, apiHash);
      _state = _windows!.currentAuthState();
    } else {
      await _api.configure(apiId, apiHash);
      _state = await _api.currentAuthState();
    }
    _configured = true;
    _log('ensureConfigured: currentAuthState=${_state.kind.name}');
    notifyListeners();
    await waitUntilReadyForAuthInput(timeout: readyTimeout);
  }

  /// Blocks until past WaitTdlibParameters (phone/QR/code/password/ready/failed).
  /// Polls native state — do not rely only on pigeon events (hot restart drops in-flight pushes).
  Future<void> waitUntilReadyForAuthInput({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_isInteractiveAuthKind(_state.kind)) {
      _log('waitUntilReadyForAuthInput: already ${_state.kind.name}');
      return;
    }

    _log('waitUntilReadyForAuthInput: polling (now=${_state.kind.name})');
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final polled = _useWindows ? _windows!.currentAuthState() : await _api.currentAuthState();
      if (polled.kind != _state.kind) {
        _log('waitUntilReadyForAuthInput: polled ${polled.kind.name}');
      }
      _state = polled;
      if (_isInteractiveAuthKind(polled.kind)) {
        notifyListeners();
        _log('waitUntilReadyForAuthInput: ready kind=${polled.kind.name}');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    notifyListeners();
    throw OxplayerTdlibBridgeException(
      'Telegram client did not finish initializing (stuck at ${_state.kind.name}). Try again.',
    );
  }

  /// Call from login-screen bootstrap before showing any auth UI.
  /// Blocks the splash until TDLib is past setTdlibParameters.
  /// When [phoneFirst] is true (phone/tablet), aborts a leftover QR session so the
  /// phone field is usable immediately.
  Future<void> prepareForLoginScreen({bool phoneFirst = true}) async {
    _log('prepareForLoginScreen phoneFirst=$phoneFirst');
    try {
      await ensureConfigured();
    } on OxplayerTdlibBridgeException catch (e) {
      if (!e.message.contains('stuck at')) rethrow;
      // Native client often still alive after hot restart with stale UNINITIALIZED cache —
      // force wipe + recreate once.
      _log('prepareForLoginScreen: stuck — forcing logOut + recreate');
      _configured = false;
      try {
        if (_useWindows) {
          await _windows!.logOut();
        } else {
          await _api.logOut();
        }
      } catch (logoutErr) {
        _log('prepareForLoginScreen: logOut during recover: $logoutErr');
      }
      await ensureConfigured();
    }
    // OX logout does not always clear Telegram — AuthReady blocks QR/phone restart.
    if (_state.kind == OxTdlibAuthStateKind.ready) {
      _log('prepareForLoginScreen: Telegram still ready — reset for re-auth');
      await resetForPhoneLogin();
    }
    if (phoneFirst && _state.kind == OxTdlibAuthStateKind.waitingForQrConfirmation) {
      await resetForPhoneLogin();
    }
    if (_state.kind == OxTdlibAuthStateKind.failed) {
      throw OxplayerTdlibBridgeException(
        _state.errorMessage ?? 'Telegram auth failed to start',
      );
    }
    if (!_isInteractiveAuthKind(_state.kind)) {
      throw OxplayerTdlibBridgeException(
        'Telegram client did not finish initializing (stuck at ${_state.kind.name}). Try again.',
      );
    }
    _log('prepareForLoginScreen done kind=${_state.kind.name}');
  }

  static const _kAuthRpcTimeout = Duration(seconds: 45);

  static bool _isPastPhoneStep(OxTdlibAuthStateKind kind) {
    switch (kind) {
      case OxTdlibAuthStateKind.waitingForCode:
      case OxTdlibAuthStateKind.waitingForPassword:
      case OxTdlibAuthStateKind.ready:
        return true;
      default:
        return false;
    }
  }

  /// Race [rpc] against [until] / timeout so flaky Telegram DCs cannot hang the UI forever.
  Future<void> _awaitAuthRpc(
    Future<void> rpc, {
    required bool Function(OxTdlibAuthStateKind kind) until,
    required String timeoutMessage,
  }) async {
    if (until(_state.kind)) return;

    final advanced = Completer<void>();
    void onState() {
      if (until(_state.kind) && !advanced.isCompleted) {
        advanced.complete();
      }
    }

    addListener(onState);
    try {
      await Future.any<void>([rpc, advanced.future]).timeout(
        _kAuthRpcTimeout,
        onTimeout: () => throw OxplayerTdlibBridgeException(timeoutMessage),
      );
    } finally {
      removeListener(onState);
    }
  }

  Future<void> submitPhoneNumber(String phoneNumber) async {
    final trimmed = phoneNumber.trim();
    _log('submitPhoneNumber len=${trimmed.length} kind=${_state.kind.name}');
    if (trimmed.isEmpty) {
      throw OxplayerTdlibBridgeException('Enter a phone number with country code');
    }
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber) {
      throw OxplayerTdlibBridgeException(
        'Telegram is not ready for phone login yet (state=${_state.kind.name})',
      );
    }
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitPhoneNumber(trimmed) : _api.submitPhoneNumber(trimmed),
      until: _isPastPhoneStep,
      timeoutMessage:
          'Could not reach Telegram (timed out). Check internet / VPN and try again.',
    );
  }

  Future<void> submitCode(String code) async {
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitCode(code) : _api.submitCode(code),
      until: (kind) =>
          kind == OxTdlibAuthStateKind.waitingForPassword ||
          kind == OxTdlibAuthStateKind.ready,
      timeoutMessage:
          'Could not verify code (timed out). Check internet / VPN and try again.',
    );
  }

  Future<void> submitTwoFactorPassword(String password) async {
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitTwoFactorPassword(password) : _api.submitTwoFactorPassword(password),
      until: (kind) => kind == OxTdlibAuthStateKind.ready,
      timeoutMessage:
          'Could not verify password (timed out). Check internet / VPN and try again.',
    );
  }

  Future<void> requestQrLogin() async {
    _log('requestQrLogin (current=${_state.kind.name})');
    await waitUntilReadyForAuthInput();
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber &&
        _state.kind != OxTdlibAuthStateKind.waitingForQrConfirmation) {
      throw OxplayerTdlibBridgeException(
        'Cannot start QR login from state=${_state.kind.name}',
      );
    }
    if (_useWindows) {
      return _windows!.requestQrLogin();
    }
    return _api.requestQrLogin();
  }

  Future<void> logOut() => _useWindows ? _windows!.logOut() : _api.logOut();

  /// True when TDLib finished AuthorizationStateReady (persisted user session on device).
  ///
  /// Used on cold start to keep OX sessions that already completed Telegram sign-in, while
  /// forcing re-login for legacy bot/deep-link OX sessions that have no MTProto session.
  /// Fail-open on configure/init errors so a transient Telegram outage does not wipe OX tokens.
  Future<bool> hasReadyUserSession({
    Duration readyTimeout = const Duration(seconds: 25),
  }) async {
    try {
      await ensureConfigured(readyTimeout: readyTimeout);
    } catch (e) {
      _log('hasReadyUserSession: ensureConfigured failed ($e) — fail-open');
      return true;
    }
    final kind = _state.kind;
    if (kind == OxTdlibAuthStateKind.ready) {
      _log('hasReadyUserSession: ready');
      return true;
    }
    // No completed Telegram user session (or mid-login leftover).
    _log('hasReadyUserSession: not ready kind=${kind.name}');
    return false;
  }

  /// OX account sign-out: wipe Telegram session without re-warming the client.
  /// Login screen [prepareForLoginScreen] / [ensureConfigured] starts a fresh client later.
  Future<void> clearSessionAfterOxLogout() async {
    _log('clearSessionAfterOxLogout from kind=${_state.kind.name}');
    try {
      await logOut();
    } catch (e) {
      _log('clearSessionAfterOxLogout logOut error (continuing): $e');
    }
    _configured = false;
    _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
    notifyListeners();
  }

  /// Abort QR (or any mid-auth) and recreate client so phone login works again.
  Future<void> resetForPhoneLogin() async {
    _log('resetForPhoneLogin from kind=${_state.kind.name}');
    try {
      await logOut();
    } catch (e) {
      _log('resetForPhoneLogin logOut error (continuing): $e');
    }
    _configured = false;
    _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
    notifyListeners();
    await ensureConfigured();
  }

  /// Resolves a PlaybackInfo Telegram source and starts progressive download.
  Future<String> startPlaybackSession(OxTdlibPlaybackSource source) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 180));
    if (_useWindows) {
      return _windows!.startPlaybackSession(source);
    }
    return _api.startPlaybackSession(source);
  }

  Future<void> stopPlaybackSession(String sessionUri) async {
    // Resolved gotdstream/http-bridge urls die with the playback session — drop cache so
    // the next play re-runs startPlaybackSession against the still-warm TDLib client.
    OxplayerTdlibSessionCache.clearAll();
    if (_useWindows) {
      await _windows!.stopPlaybackSession(sessionUri);
    } else {
      await _api.stopPlaybackSession(sessionUri);
    }
  }

  /// Fetches a Telegram-signed Mini App initData payload for TELEGRAM_WEBAPP_BOT_USERNAME (falls
  /// back to OXPLAYER_BOT_USERNAME/main-bot when no dedicated auth bot is configured).
  Future<String> fetchWebAppInitData() {
    final botUsername = OxplayerEnv.telegramWebAppBotUsername;
    if (botUsername == null) {
      throw OxplayerTdlibBridgeException('TELEGRAM_WEBAPP_BOT_USERNAME not configured');
    }
    if (_useWindows) {
      return _windows!.fetchWebAppInitData(
        botUsername,
        OxplayerEnv.telegramWebAppShortName,
        OxplayerEnv.telegramHostedWebAppHttpsUrl,
      );
    }
    return _api.fetchWebAppInitData(
      botUsername,
      OxplayerEnv.telegramWebAppShortName,
      OxplayerEnv.telegramHostedWebAppHttpsUrl,
    );
  }

  /// Full sign-in sequence: fetch a signed initData payload from TDLib, then exchange it with the
  /// backend for OX session tokens. Callers apply the result via
  /// oxplayerAuthenticateFromLoginAttemptPoll(ref, result) (same response shape as the
  /// login-attempt poll flow — both call writeJellyfinAuthenticationResult server-side).
  Future<OxplayerLoginAttemptPollResult> authenticateWithOxApi({String? deviceName}) async {
    final initData = await fetchWebAppInitData();
    final identity = await _resolveDeviceIdentity();
    final client = OxplayerTelegramWebAppAuthApi();
    return client.exchangeInitData(
      initData: initData,
      deviceId: identity,
      deviceName: deviceName,
    );
  }

  static Future<String> _resolveDeviceIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    var storedId = prefs.getString(_kOxTdlibDeviceIdPrefsKey)?.trim() ?? '';
    if (storedId.isEmpty) {
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      storedId = 'oxa-$hex';
      await prefs.setString(_kOxTdlibDeviceIdPrefsKey, storedId);
    }
    return storedId;
  }
}
