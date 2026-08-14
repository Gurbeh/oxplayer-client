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
const _kOxBotTokenPrefsKey = 'oxplayer_bot_token';
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
  OxTdlibConnectionHealth _health = OxTdlibConnectionHealth.uninitialized;
  bool _configured = false;
  /// Login-screen prepare/reset must not silently [submitBotToken] from cache.
  /// That would land TDLib on [OxTdlibAuthStateKind.ready] and the phone/QR UI
  /// would never appear (checkmark only).
  bool _suppressBotSessionRestore = false;

  bool get _useWindows => _windows != null;

  OxTdlibAuthState get state => _state;

  /// Socket liveness, independent of [state] — see [OxTdlibConnectionHealth].
  ///
  /// Windows drives playback through its own bridge and does not report health, so it stays at
  /// [OxTdlibConnectionHealth.uninitialized] there; treat that value as "unknown, don't block".
  OxTdlibConnectionHealth get connectionHealth => _health;

  /// True when credentials are valid but the socket is not usable right now.
  ///
  /// The native side is already retrying with backoff when this is true, so it is a "show a
  /// transient notice / wait" signal — never a reason to send the user back to login. Only
  /// [OxTdlibAuthStateKind.failed] means the credentials themselves need replacing.
  bool get isConnectionDegraded =>
      _state.kind == OxTdlibAuthStateKind.ready && _health == OxTdlibConnectionHealth.degraded;

  /// True when a login exists AND its connection can carry a playback download.
  ///
  /// `uninitialized` health counts as usable so this never blocks the Windows bridge or a build
  /// whose native side predates health reporting: playback then fails the old way (a real error
  /// from the download call) rather than being refused by a gate that has no information.
  bool get canStartPlayback =>
      _state.kind == OxTdlibAuthStateKind.ready && _health != OxTdlibConnectionHealth.degraded;

  /// True when native TDLib is logged in with a personal bot token (not a user phone/QR session).
  bool get nativeSessionIsBot => _activeBotToken != null && _activeBotToken!.isNotEmpty;

  Future<bool> hasCachedBotToken() async {
    if (nativeSessionIsBot) return true;
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kOxBotTokenPrefsKey);
    return cached != null && cached.isNotEmpty;
  }

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

  @override
  void onConnectionHealthChanged(OxTdlibConnectionHealth health) {
    if (_health == health) return;
    _log('connection health → ${health.name} (auth=${_state.kind.name})');
    _health = health;
    notifyListeners();
  }

  /// Revives a dead connection, returning whether playback can proceed afterwards.
  ///
  /// Cheap and safe to call on every play: the native side no-ops when the socket is already
  /// healthy. A false result means the connection could not be re-established — a network problem
  /// to report as such, NOT a reason to prompt for login, since the credentials were never in
  /// question (see [isConnectionDegraded]).
  Future<bool> ensureConnected() async {
    // Windows drives its own connection lifecycle through OxTelegramWindowsBridge and exposes no
    // health signal; there is nothing to revive from here.
    if (_useWindows) return _state.kind == OxTdlibAuthStateKind.ready;
    if (_state.kind != OxTdlibAuthStateKind.ready) return false;
    if (_health == OxTdlibConnectionHealth.ready) return true;
    try {
      await _api.reconnect();
      _health = await _api.connectionHealth();
      _log('ensureConnected → ${_health.name}');
      notifyListeners();
      return _health != OxTdlibConnectionHealth.degraded;
    } catch (e) {
      _log('ensureConnected failed: $e');
      return false;
    }
  }

  /// Serializes concurrent ensureConfigured callers onto one in-flight attempt instead of each
  /// kicking off its own native configure/restore — confirmed a real bug: several
  /// dashboard-slider items prefetching at once each raced their own bot-token restore
  /// (ensureBotSessionFromCacheIfNeeded → submitBotToken) against the others, and the native
  /// side losing that race would reset to uninitialized, which the next prefetch's
  /// ensureConfigured then saw and "fixed" by reconfiguring — repeating forever, and starving
  /// the real play action of a state that ever settled.
  Future<void>? _ensureConfiguredInFlight;

  /// Idempotent — safe to call from every login panel's initState, and from every prefetch/play
  /// attempt (see _ensureConfiguredInFlight — concurrent callers share one attempt).
  /// Waits until TDLib accepts phone/QR input (past setTdlibParameters) — for bot-mode sessions,
  /// also tries to restore a previously-connected bot from local cache if the native state isn't
  /// already ready (see ensureBotSessionFromCacheIfNeeded), so both prefetch and the real play
  /// action see the same, fully-restored state without either needing to know about the other.
  Future<void> ensureConfigured({
    Duration readyTimeout = const Duration(seconds: 45),
  }) {
    final inFlight = _ensureConfiguredInFlight;
    if (inFlight != null) return inFlight;
    final future = _ensureConfiguredLocked(readyTimeout);
    _ensureConfiguredInFlight = future;
    future.whenComplete(() {
      if (identical(_ensureConfiguredInFlight, future)) {
        _ensureConfiguredInFlight = null;
      }
    });
    return future;
  }

  Future<void> _ensureConfiguredLocked(Duration readyTimeout) async {
    if (_configured) {
      // Don't trust the cached flag alone — re-verify against native's actual current state.
      // Observed in practice: _configured stays true (this singleton survives Dart hot restarts)
      // while native's auth state regresses to uninitialized, with nothing left to call
      // configure() again and drive it forward — waitUntilReadyForAuthInput then polls a dead
      // state for the full timeout instead of failing fast or self-healing.
      final polled = _useWindows ? _windows!.currentAuthState() : await _api.currentAuthState();
      if (polled.kind != OxTdlibAuthStateKind.uninitialized &&
          polled.kind != OxTdlibAuthStateKind.failed) {
        _state = polled;
        _log('ensureConfigured: already configured kind=${_state.kind.name}');
        await waitUntilReadyForAuthInput(timeout: readyTimeout);
        await _restoreBotSessionIfNeededLocked();
        return;
      }
      // `failed` is treated exactly like `uninitialized`, not like a configured state. It is what
      // native lands in when a cold-start RPC fails, and it used to be cached the same way `ready`
      // was: every later play logged "already configured kind=failed" and never retried, so the
      // app stayed dead until it was force-killed (seen on Xiaomi). Re-submitting a cached bot
      // token onto that client does not help either — the client itself is the thing that is
      // broken, so the fix is a real reconfigure. Same failure shape, and same remedy, as the dead
      // run loop handled in go/oxtelegram/client.go's Configure.
      _log('ensureConfigured: cached configured=true but native reports ${polled.kind.name} — reconfiguring');
      _configured = false;
      if (polled.kind == OxTdlibAuthStateKind.failed) {
        // Tear the corpse down first: configure() on the native side is idempotent on "already
        // have a client", so without this it would return the same dead client straight back.
        try {
          if (_useWindows) {
            await _windows!.logOut();
          } else {
            await _api.logOut();
          }
        } catch (e) {
          // Expected to fail sometimes — we are tearing down something already broken. The
          // configure() below is what actually has to work.
          _log('ensureConfigured: teardown before failed-state reconfigure threw: $e');
        }
      }
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
    await _restoreBotSessionIfNeededLocked();
  }

  /// Only ever called from inside _ensureConfiguredLocked (hence "Locked" — under the same
  /// single-flight guard as the rest of ensureConfigured, not a separate entry point). A no-op
  /// unless state is waitingForPhoneNumber (fresh/unauthenticated) and a bot token is cached —
  /// see submitBotToken's caching and ensureBotSessionFromCacheIfNeeded's fuller doc comment.
  Future<void> _restoreBotSessionIfNeededLocked() async {
    if (_suppressBotSessionRestore) {
      _log('restoreBotSession: skipped (login-screen auth)');
      return;
    }
    if (_state.kind != OxTdlibAuthStateKind.ready) {
      await ensureBotSessionFromCacheIfNeeded();
    }
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
    _suppressBotSessionRestore = true;
    try {
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
      if (_state.kind == OxTdlibAuthStateKind.ready) {
        throw OxplayerTdlibBridgeException(
          'Telegram session was still signed in after reset. Tap Retry.',
        );
      }
      _log('prepareForLoginScreen done kind=${_state.kind.name}');
    } finally {
      _suppressBotSessionRestore = false;
    }
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

  /// Bot-token login: an alternative to phone/QR for users who don't want to give OXPlayer
  /// access to their personal Telegram account. Goes straight to `ready` — no code/2FA step.
  /// Everything downstream (state, startPlaybackSession, stopPlaybackSession, logOut) is
  /// unchanged by which of the two paths got here — callers never need to know or branch on it.
  /// Native (auth.go SubmitBotToken/checkInitialStatus) has no state restriction on when this can
  /// be called — a transient RPC failure at cold start (checkInitialStatus's Auth().Status call,
  /// or a previous SubmitBotToken attempt) lands in `failed`, and calling this again from there is
  /// exactly how ensureBotSessionFromCacheIfNeeded recovers (see its widened guard below).
  Future<void> submitBotToken(String token) async {
    final trimmed = token.trim();
    _log('submitBotToken len=${trimmed.length} kind=${_state.kind.name}');
    if (trimmed.isEmpty) {
      throw OxplayerTdlibBridgeException('Enter your bot token');
    }
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber) {
      throw OxplayerTdlibBridgeException(
        'Telegram is not ready for bot-token login yet (state=${_state.kind.name})',
      );
    }
    await _awaitAuthRpc(
      _useWindows ? _windows!.submitBotToken(trimmed) : _api.submitBotToken(trimmed),
      until: (kind) => kind == OxTdlibAuthStateKind.ready,
      timeoutMessage:
          'Could not reach Telegram (timed out). Check internet / VPN and try again.',
    );
    _activeBotToken = trimmed;
    // Cached so a later app start (or a fresh install's first playback attempt) can silently
    // re-apply it via ensureBotSessionFromCacheIfNeeded, without needing the OX session/access
    // token threaded all the way down here again.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOxBotTokenPrefsKey, trimmed);
  }

  String? _activeBotToken;
  Future<void>? _ensureBotTokenInFlight;
  String? _ensureBotTokenTarget;

  /// Logs native TDLib in as [token] (personal bot). Tears down a leftover user/QR session first —
  /// [submitBotToken] only accepts `waitingForPhoneNumber`, so a previous client-session login
  /// otherwise stays `ready` while the API copies into `@userbot`. Play then waits 20s on the
  /// wrong account.
  Future<void> ensureBotTokenSession(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return Future.error(OxplayerTdlibBridgeException('Enter your bot token'));
    }
    if (_state.kind == OxTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return Future.value();
    }
    if (_ensureBotTokenInFlight != null && _ensureBotTokenTarget == trimmed) {
      return _ensureBotTokenInFlight!;
    }
    final future = _ensureBotTokenSessionLocked(trimmed);
    _ensureBotTokenInFlight = future;
    _ensureBotTokenTarget = trimmed;
    future.whenComplete(() {
      if (identical(_ensureBotTokenInFlight, future)) {
        _ensureBotTokenInFlight = null;
        _ensureBotTokenTarget = null;
      }
    });
    return future;
  }

  Future<void> _ensureBotTokenSessionLocked(String trimmed) async {
    if (_state.kind == OxTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOxBotTokenPrefsKey, trimmed);
    _log('ensureBotTokenSession: switching to personal bot from kind=${_state.kind.name}');

    Future<void> tearDownNativeSession() async {
      try {
        await logOut();
      } catch (e) {
        _log('ensureBotTokenSession: logOut: $e');
      }
      _configured = false;
      _activeBotToken = null;
    }

    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber) {
      await tearDownNativeSession();
      await ensureConfigured();
    }
    if (_state.kind == OxTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber) {
      await tearDownNativeSession();
      await ensureConfigured();
    }
    if (_state.kind == OxTdlibAuthStateKind.ready && _activeBotToken == trimmed) {
      return;
    }
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber) {
      throw OxplayerTdlibBridgeException(
        'Telegram is not ready for bot-token login yet (state=${_state.kind.name})',
      );
    }
    await submitBotToken(trimmed);
  }

  /// Lazily re-applies a previously-connected bot token when this device's native session isn't
  /// authenticated yet — the gap that caused a real bug: a returning bot-mode user whose native
  /// bridge was configured on a fresh login (see OxplayerMainBotLoginPanel) but never again on
  /// subsequent app starts, so playback hit AUTH_KEY_UNREGISTERED via the session-mode resolve
  /// path instead of ever reaching bot-mode at all. No-op if already ready, or nothing cached
  /// (i.e. this really is a session-mode/TDLib user, or a bot-mode user who hasn't connected a
  /// bot yet at all — callers distinguish those via the thrown exception, not this method).
  ///
  /// Retries from `failed` too, not just `waitingForPhoneNumber`: confirmed on-device that a
  /// transient cold-start RPC hiccup (checkInitialStatus's Auth().Status call in auth.go) lands
  /// native in `failed`, and once there this method used to return immediately every time —
  /// _ensureConfiguredLocked treats non-uninitialized state as "already configured" and skips
  /// reconfigure, so the app got permanently stuck reporting "bot isn't connected" despite a
  /// perfectly valid cached token, on every single playback attempt, with no retry path at all.
  Future<void> ensureBotSessionFromCacheIfNeeded() async {
    if (_state.kind == OxTdlibAuthStateKind.ready) return;
    if (_state.kind != OxTdlibAuthStateKind.waitingForPhoneNumber &&
        _state.kind != OxTdlibAuthStateKind.failed) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kOxBotTokenPrefsKey);
    if (cached == null || cached.isEmpty) return;
    _log('ensureBotSessionFromCacheIfNeeded: re-applying cached bot token');
    try {
      await submitBotToken(cached);
    } catch (e) {
      // Token was revoked/bot deleted since it was cached — surface nothing here, let the
      // caller's own ready-check after this call produce the real "reconnect your bot" error.
      _log('ensureBotSessionFromCacheIfNeeded: cached token no longer works: $e');
    }
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
    _activeBotToken = null;
    _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
    notifyListeners();
  }

  /// Abort QR (or any mid-auth) and recreate client so phone login works again.
  Future<void> resetForPhoneLogin() async {
    _log('resetForPhoneLogin from kind=${_state.kind.name}');
    final previousSuppress = _suppressBotSessionRestore;
    _suppressBotSessionRestore = true;
    try {
      try {
        await logOut();
      } catch (e) {
        _log('resetForPhoneLogin logOut error (continuing): $e');
      }
      _configured = false;
      _activeBotToken = null;
      _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
      notifyListeners();
      await ensureConfigured();
    } finally {
      _suppressBotSessionRestore = previousSuppress;
    }
  }

  /// Resolves a PlaybackInfo Telegram source and starts progressive download.
  ///
  /// Throws [OxplayerTdlibBridgeException] with a clear, user-facing message — not a raw native
  /// PlatformException/AUTH_KEY_UNREGISTERED stack trace — when the native session isn't
  /// authenticated at all. That used to be silently attempted anyway (a real bug: a bot-mode
  /// user's native bridge only ever got configured right after a fresh login, never again on
  /// later app starts, so returning users hit the native call with kind still
  /// waitingForPhoneNumber and got an opaque AUTH_KEY_UNREGISTERED crash instead of a clear
  /// "reconnect your bot" message).
  Future<String> startPlaybackSession(OxTdlibPlaybackSource source) async {
    // ensureConfigured already tries the cached-bot-token restore (see
    // _restoreBotSessionIfNeededLocked) — under the same single-flight guard every other
    // concurrent caller (prefetch included) shares, so this doesn't race a separate attempt.
    await ensureConfigured(readyTimeout: const Duration(seconds: 180));
    if (_state.kind != OxTdlibAuthStateKind.ready) {
      throw OxplayerTdlibBridgeException(
        "Your personal bot isn't connected. In Telegram, send /connectbot to "
        "@${OxplayerEnv.botUsername ?? 'main-bot'} to reconnect it, then try again.",
      );
    }
    if (_useWindows) {
      return _windows!.startPlaybackSession(source);
    }
    return _api.startPlaybackSession(source);
  }

  /// Where the native session actually read [locator], or null. Reported to the backend so the
  /// next play of the same file skips the copy — see OxplayerTelegramDeliveryApi. Never throws: a
  /// failure here only costs one redundant copy.
  Future<OxTdlibDeliveryRef?> deliveryRefForLocator(String locator) async {
    try {
      if (_useWindows) {
        return _windows!.deliveryRefForLocator(locator);
      }
      return await _api.deliveryRefForLocator(locator);
    } catch (e) {
      _log('deliveryRefForLocator failed: $e');
      return null;
    }
  }

  /// Registers interest in [locator] BEFORE the PlaybackInfo call that triggers the copy, so a
  /// delivery landing while that request is still in flight is captured rather than raced for.
  /// Never throws — the native buffer already tolerates an unarmed early arrival, this only
  /// narrows the window.
  Future<void> armDeliveryWaiter(String locator) async {
    if (locator.isEmpty) return;
    try {
      if (_useWindows) {
        _windows!.armDeliveryWaiter(locator);
      } else {
        await _api.armDeliveryWaiter(locator);
      }
    } catch (e) {
      _log('armDeliveryWaiter failed: $e');
    }
  }

  /// Resolves [source] and records where it landed WITHOUT opening a download — the warm-up path.
  /// Requires a ready session, like [startPlaybackSession], but deliberately starts no byte
  /// transfer: warming a dashboard row must not spend the user's data on a dozen videos nobody
  /// pressed play on.
  Future<void> warmDelivery(OxTdlibPlaybackSource source) async {
    await ensureConfigured(readyTimeout: const Duration(seconds: 60));
    if (_state.kind != OxTdlibAuthStateKind.ready) return;
    if (_useWindows) {
      await _windows!.warmDelivery(source);
      return;
    }
    await _api.warmDelivery(source);
  }

  /// Blocks until the session is [OxTdlibAuthStateKind.ready] (user logged in, not merely past
  /// setTdlibParameters). Distinct from [waitUntilReadyForAuthInput], which returns at
  /// waitingForPhoneNumber — too early to startBot.
  Future<bool> waitUntilSessionReady({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_state.kind == OxTdlibAuthStateKind.ready) return true;
    final done = Completer<void>();
    void onState() {
      if (_state.kind == OxTdlibAuthStateKind.ready && !done.isCompleted) {
        done.complete();
      }
    }
    addListener(onState);
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      _log('waitUntilSessionReady timed out kind=${_state.kind.name}');
    } finally {
      removeListener(onState);
    }
    return _state.kind == OxTdlibAuthStateKind.ready;
  }

  /// Starts, mutes and archives every delivery sender on this account so delivery copies never
  /// land in the user's visible inbox. Called on every app enter — a sender can be added to the
  /// backend's list at any time, and a user who never re-logs in would otherwise never start it.
  ///
  /// Returns false when the session is not ready (caller must retry, not mark the job done).
  /// Never throws: a failed startBot on one sender must not take playback down.
  Future<bool> ensureProviderBotsReady(List<OxTdlibProviderBot> bots) async {
    if (bots.isEmpty) return true;
    try {
      await ensureConfigured(readyTimeout: const Duration(seconds: 60));
      if (_state.kind != OxTdlibAuthStateKind.ready) {
        final ready = await waitUntilSessionReady();
        if (!ready) {
          _log('ensureProviderBotsReady skipped — auth kind=${_state.kind.name}');
          return false;
        }
      }
      if (_useWindows) {
        await _windows!.ensureProviderBotsReady(bots);
      } else {
        await _api.ensureProviderBotsReady(bots);
      }
      _log('ensureProviderBotsReady ok for ${bots.length} bot(s)');
      return true;
    } catch (e) {
      _log('ensureProviderBotsReady failed: $e');
      return false;
    }
  }

  Future<void> stopPlaybackSession(String sessionUri) async {
    // Belt and braces: OxplayerTdlibSessionCache refuses to store session-bound urls in the first
    // place, so this normally clears nothing. Kept so that a resolved url reaching the cache by any
    // future path still cannot outlive the session being torn down here.
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
    final identity = await resolveDeviceIdentity();
    final client = OxplayerTelegramWebAppAuthApi();
    return client.exchangeInitData(
      initData: initData,
      deviceId: identity,
      deviceName: deviceName,
    );
  }

  static Future<String> resolveDeviceIdentity() async {
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
