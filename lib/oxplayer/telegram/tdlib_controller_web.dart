import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:web/web.dart';

import 'oxplayer_tdlib_debug.dart';
import 'tdlib_facade.dart';
import 'utils/tdlib_wire_json_compat.dart';

void _tdlog(String message) {
  if (kDebugMode) debugPrint(message);
}

String _stringifyTdWebSendFailure(Object e) {
  if (e is td.TdError) {
    return '${e.message} (code ${e.code})';
  }
  try {
    final dyn = e as dynamic;
    final m = dyn.message;
    if (m is String && m.isNotEmpty) {
      return m;
    }
    final s = dyn.toString();
    if (s.isNotEmpty && s != 'Instance of \'LegacyJavaScriptObject\'') {
      return s;
    }
  } catch (_) {}
  final s = e.toString();
  if (s.contains('[object Object]') || s.contains('LegacyJavaScriptObject')) {
    return 'Telegram request failed (see browser console).';
  }
  return s;
}

/// TDLib JSON [toJson] may include null `@extra`; tdweb/JSON.stringify tolerates it but
/// stripping keeps the wire minimal.
String _jsonEncodeTdFunction(td.TdFunction fn) {
  final m = Map<String, dynamic>.from(fn.toJson());
  m.removeWhere((_, v) => v == null);
  return jsonEncode(m);
}

const _kMaxGetMeRetries = 2;

TelegramTdlibFacade? _webActiveFacade;

JSObject get _windowObj => window as JSObject;

/// tdweb calls this with a real JS string; [dartify] alone can miss it on some web targets.
String _jsAnyToDartJsonString(JSAny? value) {
  if (value == null) return '';
  try {
    return (value as JSString).toDart;
  } catch (_) {}
  try {
    final d = value.dartify();
    if (d is String) return d;
    return d?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

void _oxplayerTdwebDartPush(JSAny? raw) {
  final facade = _webActiveFacade;
  if (facade == null) {
    if (kDebugMode) {
      debugPrint('[OX TD web] oxplayerTdwebDartPush: dropped (no active facade)');
    }
    return;
  }
  final s = _jsAnyToDartJsonString(raw);
  if (s.isEmpty) {
    if (kDebugMode) {
      debugPrint('[OX TD web] oxplayerTdwebDartPush: dropped (empty JSON string)');
    }
    return;
  }
  unawaited(facade._dispatchIncomingJson(s));
}

JSObject? _bridgeObj() {
  final v = _windowObj['oxplayerTdweb'];
  return v as JSObject?;
}

class TelegramTdlibFacade implements TdTelegramClient {
  TelegramTdlibFacade({
    this.onUserAuthorized,
    this.onRequiresInteractiveLogin,
  });

  final Future<void> Function(td.User user)? onUserAuthorized;
  final Future<void> Function()? onRequiresInteractiveLogin;

  static TelegramTdlibFacade? _singletonOwner;
  static Future<void> _globalInitSerial = Future.value();

  bool _webJsAlive = false;
  int _webSessionEpoch = 0;
  /// Blocks [getAuthorizationState] polling while [setTdlibParameters] is in flight (tdweb WASM crash).
  bool _authPollPaused = false;
  int _tdwebInitFatalRecoveryAttempts = 0;
  /// Set when tdweb posts [updateFatalError] (not modeled as a typed [TdObject]).
  bool _receivedTdlibFatal = false;

  /// Last fatal detail from tdweb (also printed as `TDLib fatal: …` for console search).
  String? _lastTdlibFatalDetail;

  /// Wire `@type` when WASM returns an [AuthorizationState] shape the typed parser does not cover.
  /// ([convertToObject] is null; [AuthorizationState.fromJson] yields a bare shell).
  String? _pendingAuthStateWireType;

  /// Non-null stops auth probing and rejects further [send] until [init] runs again.
  String? _unsupportedAuthWire;

  /// Same value sent in [SetTdlibParameters.databaseEncryptionKey] (often empty on web).
  String _databaseEncryptionKeyApplied = '';

  /// One-shot per init for [authorizationStateWaitEncryptionKey] when JSON is handled manually.
  bool _databaseEncryptionKeyProbeSent = false;

  int? _pendingApiId;
  String? _pendingApiHash;
  bool _paramsSent = false;
  bool _awaitingGetMeAfterReady = false;
  int _getMeRetryCount = 0;
  final _updates = StreamController<Map<String, dynamic>>.broadcast();
  final _qrPayload = StreamController<String?>.broadcast();
  final _cloudPassword = StreamController<TdlibCloudPasswordChallenge?>.broadcast();
  final _smsCodeChallenge = StreamController<TdlibSmsCodeChallenge?>.broadcast();
  final _authWaitPhoneNumber = StreamController<bool>.broadcast();
  final _authUserId = StreamController<int>.broadcast();
  final _functionErrors = StreamController<String?>.broadcast();
  var _authCompleter = Completer<void>();
  Future<void> _finalizeChain = Future.value();
  Completer<void>? _closeHandshakeCompleter;

  @override
  bool get isInitialized => _webJsAlive;

  bool _hasReachedAuthorizationWaitPhoneNumber = false;

  @override
  bool get hasReachedAuthorizationWaitPhoneNumber =>
      _hasReachedAuthorizationWaitPhoneNumber;

  @override
  Stream<Map<String, dynamic>> updates() => _updates.stream;

  @override
  Stream<String?> get qrLoginPayload => _qrPayload.stream;

  @override
  Stream<TdlibCloudPasswordChallenge?> get cloudPasswordChallenge => _cloudPassword.stream;

  @override
  Stream<TdlibSmsCodeChallenge?> get smsCodeChallenge => _smsCodeChallenge.stream;

  @override
  Stream<bool> get authorizationWaitPhoneNumber => _authWaitPhoneNumber.stream;

  @override
  Stream<int> get authenticatedUserId => _authUserId.stream;

  @override
  Stream<String?> get functionErrors => _functionErrors.stream;

  @override
  Future<void> ensureAuthorized() => _authCompleter.future;

  static bool _tdwebGlobalsPresent() {
    return _windowObj.has('tdweb') && _windowObj.has('oxplayerTdweb');
  }

  static Future<void> initTdlibPlugin() async {
    if (!_tdwebGlobalsPresent()) {
      throw StateError(
        'Telegram web sign-in failed to load. Hard-refresh the page or reinstall the app.',
      );
    }
  }

  void _registerDartPushHandler() {
    _webActiveFacade = this;
    _windowObj['oxplayerTdwebDartPush'] = _oxplayerTdwebDartPush.toJS;
  }

  String _stringifyTdwebFatalFragment(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    if (value is Map) {
      final m = Map<String, dynamic>.from(value);
      final inner = _stringifyTdwebFatalFragment(
        m['message'] ?? m['error'] ?? m['text'],
      );
      if (inner.isNotEmpty) return inner;
      try {
        return jsonEncode(m);
      } catch (_) {
        return m.toString();
      }
    }
    return value.toString();
  }

  bool _isUselessFatalDetail(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (t == '{}' || t == '()' || t == '[]') return true;
    if (t == 'null') return true;
    return false;
  }

  String _formatTdwebFatalPayload(Map<String, dynamic> map) {
    final combined = _stringifyTdwebFatalFragment(
      map['error'] ?? map['message'] ?? map['fatal_error'],
    );
    if (!_isUselessFatalDetail(combined)) return combined;
    try {
      final encoded = jsonEncode(map);
      if (!_isUselessFatalDetail(encoded)) return encoded;
    } catch (_) {}
    return 'unknown fatal error (no readable message from tdweb; '
        'see browser console for "[OX_TG_WEB_STREAM] updateFatalError" and refresh '
        'after fixing API keys or clearing site data).';
  }

  void _handleTdwebUpdateFatalError(Map<String, dynamic> map) {
    final msg = _formatTdwebFatalPayload(map);
    _lastTdlibFatalDetail = msg;
    if (kDebugMode) debugPrint('TDLib fatal: $msg');
    _tdlog('TDLib web ← updateFatalError: $msg');

    final canRecoverFromInitFatal =
        !_hasReachedAuthorizationWaitPhoneNumber &&
        _tdwebInitFatalRecoveryAttempts < 1 &&
        _pendingApiId != null &&
        _pendingApiHash != null &&
        _webJsAlive;
    if (canRecoverFromInitFatal) {
      _tdwebInitFatalRecoveryAttempts += 1;
      unawaited(_recoverTdwebAfterInitFatal());
      return;
    }

    _receivedTdlibFatal = true;
    final lower = msg.toLowerCase();
    final runningDiffFatal =
        lower.contains('running_get_difference_') ||
        (lower.contains('notificationmanager') && lower.contains('check') && lower.contains('failed'));
    if (runningDiffFatal && !_functionErrors.isClosed) {
      _functionErrors.add(
        'TDLib local web session is corrupted (running_get_difference failed). '
        'Close other OXPlayer tabs for this origin, clear site data/IndexedDB, and restart Telegram login.',
      );
    }
    if (!_functionErrors.isClosed) {
      _functionErrors.add('TDLib fatal: $msg');
    }
  }

  Future<void> _dispatchIncomingJson(String raw) async {
    try {
      final quickRaw = parseTdJsonObjectMap(raw);
      if (quickRaw != null &&
          quickRaw['@type']?.toString() == 'updateFatalError') {
        _handleTdwebUpdateFatalError(quickRaw);
        return;
      }
      final sanitized = raw;
      final quick = parseTdJsonObjectMap(sanitized);
      if (quick != null && quick['@type']?.toString() == 'updateFatalError') {
        _handleTdwebUpdateFatalError(quick);
        return;
      }

      final obj = td.convertToObject(tdJsonPrepareForConvertToObject(sanitized));
      if (obj == null) {
        try {
          final t = quick?['@type'];
          _tdlog('TDLib web convertToObject returned null (@type=$t)');
        } catch (_) {
          _tdlog('TDLib web convertToObject returned null (invalid JSON head)');
        }
        return;
      }

      if (obj is td.UpdateAuthorizationState) {
        _tdlog(
          'TDLib web ← updateAuthorizationState: '
          '${obj.authorizationState.runtimeType}',
        );
      } else if (obj is td.TdError) {
        _tdlog('TDLib web ← TdError code=${obj.code} message=${obj.message}');
      }

      final jsonMap = _tdObjectToJson(obj);
      if (jsonMap != null) {
        _updates.add(jsonMap);
      }

      if (obj is td.TdError) {
        _handleTdError(obj);
      } else {
        _handleAuthorization(obj);
        _handleSessionUser(obj);
      }
    } catch (error, stackTrace) {
      final len = raw.length;
      final head = len > 600 ? '${raw.substring(0, 600)}…' : raw;
      final peek = tdlibJsonPeekForLog(raw);
      var preppedPeek = 'prep_unavailable';
      try {
        final s = tdJsonPrepareForConvertToObject(raw);
        final m = parseTdJsonObjectMap(s);
        preppedPeek = m?['@type']?.toString() ?? 'prep_null_map';
      } catch (e) {
        preppedPeek = 'prep_error: $e';
      }
      _tdlog(
        '[TDLib web rx] DISPATCH_FAIL step=convertToObject peek=$peek '
        'preppedPeek=$preppedPeek rawLen=$len',
      );
      _tdlog('TDLib web dispatch error: $error\n$stackTrace');
      _tdlog('[TDLib web rx] raw head (max 600ch): $head');
    }
  }

  Future<void> _jsCreateClient() async {
    final bridge = _bridgeObj();
    if (bridge == null) {
      throw StateError('oxplayerTdweb bridge missing (oxplayer_tdweb_bridge.js).');
    }
    final opts = <String, dynamic>{'instanceEpoch': _webSessionEpoch}.jsify();
    final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
      'createClient'.toJS,
      <JSAny?>[opts],
    );
    await promise.toDart;
  }

  /// tdweb only processes [TdClient.send] after the worker reaches `inited` and posts `start`.
  /// Sending earlier leaves the JS promise pending forever (no Dart logs, no auth progress).
  Future<void> _jsWaitTdwebInited() async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    var checks = 0;
    while (DateTime.now().isBefore(deadline)) {
      final bridge = _bridgeObj();
      if (bridge == null) return;
      try {
        final r = bridge.callMethodVarArgs<JSAny?>(
          'isTdwebInited'.toJS,
          const <JSAny?>[],
        );
        final d = r?.dartify();
        if (d == true) {
          _tdlog('TDLib web: tdweb isInited=true (after $checks polls)');
          return;
        }
      } catch (e) {
        _tdlog('TDLib web isTdwebInited check failed: $e');
      }
      checks += 1;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _tdlog(
      'TDLib web: isTdwebInited still false after 12s — continuing (re-run `node scripts/sync-tdweb.mjs` if worker paths are wrong)',
    );
  }

  Future<void> _jsCloseClient() async {
    final bridge = _bridgeObj();
    if (bridge == null) return;
    final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
      'closeClient'.toJS,
      const <JSAny?>[],
    );
    await promise.toDart;
  }

  Future<String> _jsSendJson(String jsonStr) async {
    final bridge = _bridgeObj();
    if (bridge == null) {
      throw StateError('oxplayerTdweb bridge missing.');
    }
    final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
      'send'.toJS,
      <JSAny?>[jsonStr.toJS],
    );
    final result = await promise.toDart;
    final s = _jsAnyToDartJsonString(result);
    return s.isEmpty ? 'null' : s;
  }

  void _enginePost(td.TdFunction fn) {
    if (!_webJsAlive) return;
    final payload = _jsonEncodeTdFunction(fn);
    unawaited(
      _jsSendJson(payload).catchError((Object e) {
        _tdlog(
          'TDLib web fire-and-forget send failed: ${_stringifyTdWebSendFailure(e)}',
        );
        return '';
      }),
    );
  }

  /// Newer TDLib WASM may enter [authorizationStateWaitEncryptionKey]; the scheme may omit a typed check function.
  Future<void> _submitDatabaseEncryptionKeyProbe() async {
    if (!_webJsAlive || _databaseEncryptionKeyProbeSent) return;
    _databaseEncryptionKeyProbeSent = true;
    try {
      _tdlog(
        'TDLib web → checkDatabaseEncryptionKey (encryption_key len='
        '${_databaseEncryptionKeyApplied.length})',
      );
      final extra =
          '${DateTime.now().microsecondsSinceEpoch}_checkDatabaseEncryptionKey';
      final raw = await _jsSendJson(
        jsonEncode({
          '@type': 'checkDatabaseEncryptionKey',
          'encryption_key': _databaseEncryptionKeyApplied,
          '@extra': extra,
        }),
      );
      final sanitized = raw;
      final obj = td.convertToObject(tdJsonPrepareForConvertToObject(sanitized));
      if (obj is td.TdError) {
        _databaseEncryptionKeyProbeSent = false;
        final m =
            'TDLib rejected database encryption key (${obj.message}). '
            'Clear site data for this site (IndexedDB) if you never set a password, then reload.';
        if (!_functionErrors.isClosed) {
          _functionErrors.add(m);
        }
        _tdlog('TDLib web checkDatabaseEncryptionKey TdError: ${obj.message}');
        return;
      }
      if (obj is td.Ok) {
        _tdlog('TDLib web checkDatabaseEncryptionKey → ok');
      } else {
        _tdlog(
          'TDLib web checkDatabaseEncryptionKey unexpected: ${obj?.runtimeType}',
        );
      }
    } catch (e) {
      _databaseEncryptionKeyProbeSent = false;
      _tdlog('TDLib web checkDatabaseEncryptionKey failed: $e');
    }
  }

  @override
  Future<td.TdObject> send(td.TdFunction request) async {
    if (!_webJsAlive) {
      return Future.error(StateError('Telegram sign-in is not ready yet.'));
    }
    if (_receivedTdlibFatal) {
      final detail = _lastTdlibFatalDetail;
      final extra = (detail != null && detail.isNotEmpty) ? ': $detail' : '';
      return Future.error(
        StateError(
          'Telegram sign-in failed$extra. Refresh the page and try again.',
        ),
      );
    }
    if (_unsupportedAuthWire != null) {
      return Future.error(
        StateError(
          'Telegram sign-in is blocked at an unsupported step ("$_unsupportedAuthWire"). '
          'Update the app or refresh and try again.',
        ),
      );
    }
    final extra = '${DateTime.now().microsecondsSinceEpoch}_${request.runtimeType}';
    final payload = jsonEncode(request.toJson(extra));
    final raw = await _jsSendJson(payload);
    final sanitized = raw;
    final prepped = tdJsonPrepareForConvertToObject(sanitized);
    td.TdObject? resolved = td.convertToObject(prepped);
    if (resolved != null) {
      _pendingAuthStateWireType = null;
    } else {
      final map = parseTdJsonObjectMap(prepped);
      final t = map?['@type']?.toString();
      if (map != null &&
          t != null &&
          t.startsWith('authorizationState')) {
        resolved = td.AuthorizationState.fromJson(map);
        final ctor = resolved.getConstructor();
        if (ctor == 'authorizationState' && t != 'authorizationState') {
          _pendingAuthStateWireType = t;
        } else {
          _pendingAuthStateWireType = null;
        }
      }
      if (resolved == null) {
        final head =
            prepped.length > 280 ? '${prepped.substring(0, 280)}…' : prepped;
        return Future.error(
          StateError(
            'TDLib returned null object (@type=${t ?? "missing"}). Raw: $head',
          ),
        );
      }
    }
    if (resolved is td.TdError) {
      return Future.error(resolved, StackTrace.current);
    }
    return resolved;
  }

  static Future<void> _forceReclaimWebClient(TelegramTdlibFacade caller) async {
    final sibling = _singletonOwner;
    if (sibling == null || identical(sibling, caller)) return;
    await sibling._shutdownClient();
    _singletonOwner = null;
  }

  @override
  Future<void> init({
    required int apiId,
    required String apiHash,
    required String sessionString,
  }) async {
    if (apiId <= 0 || apiHash.isEmpty) {
      throw StateError(
        'Set TELEGRAM_API_ID and TELEGRAM_API_HASH via dart-define/dart-define-from-file '
        'or assets/env/default.env.',
      );
    }
    final previousGlobal = _globalInitSerial;
    final doneGlobal = Completer<void>();
    _globalInitSerial = doneGlobal.future;
    try {
      await previousGlobal.catchError((Object _, StackTrace __) {});
      await _performInit(apiId: apiId, apiHash: apiHash, sessionString: sessionString);
    } finally {
      if (!doneGlobal.isCompleted) {
        doneGlobal.complete();
      }
    }
  }

  Future<void> _performInit({
    required int apiId,
    required String apiHash,
    required String sessionString,
  }) async {
    await _shutdownClient();
    await _forceReclaimWebClient(this);

    _receivedTdlibFatal = false;
    _lastTdlibFatalDetail = null;
    _pendingAuthStateWireType = null;
    _unsupportedAuthWire = null;
    _databaseEncryptionKeyApplied = '';
    _databaseEncryptionKeyProbeSent = false;
    _authPollPaused = false;
    _tdwebInitFatalRecoveryAttempts = 0;

    if (sessionString.isNotEmpty && kDebugMode) {
      if (kDebugMode) {
        debugPrint('TDLib web: session string is ignored; IndexedDB + instanceName are used.');
      }
    }

    await initTdlibPlugin();

    _pendingApiId = apiId;
    _pendingApiHash = apiHash;
    _paramsSent = false;
    _hasReachedAuthorizationWaitPhoneNumber = false;
    _awaitingGetMeAfterReady = false;
    _getMeRetryCount = 0;
    if (_authCompleter.isCompleted) {
      _authCompleter = Completer<void>();
    }
    _finalizeChain = Future.value();

    _registerDartPushHandler();
    _webJsAlive = true;
    try {
      await _jsCreateClient();
      await _jsWaitTdwebInited();
    } catch (e) {
      _webJsAlive = false;
      if (identical(_webActiveFacade, this)) {
        _webActiveFacade = null;
      }
      rethrow;
    }
    _singletonOwner = this;
    unawaited(_bootstrapAuthorizationStatePolling());
  }

  static const Duration _kTdwebAuthProbeTimeout = Duration(seconds: 12);

  Future<td.TdObject> _sendAuthProbe(td.TdFunction request) {
    return send(request).timeout(
      _kTdwebAuthProbeTimeout,
      onTimeout: () => throw TimeoutException(
        'TDLib web: ${request.runtimeType}',
        _kTdwebAuthProbeTimeout,
      ),
    );
  }

  /// tdweb [onUpdate] is unreliable on some Flutter web targets; drive auth with [getAuthorizationState].
  Future<void> _bootstrapAuthorizationStatePolling() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration(milliseconds: i == 0 ? 50 : 200));
      if (!_webJsAlive || _receivedTdlibFatal || _unsupportedAuthWire != null) {
        return;
      }
      if (_authPollPaused) {
        continue;
      }
      try {
        _tdlog('TDLib web boot poll[$i] → getAuthorizationState…');
        final r = await _sendAuthProbe(const td.GetAuthorizationState());
        if (r is! td.AuthorizationState) {
          _tdlog('TDLib web boot poll[$i] unexpected type: ${r.runtimeType}');
          continue;
        }
        _tdlog('TDLib web boot poll[$i] → ${r.runtimeType}');
        _applyAuthorizationState(r);
        if (r is td.AuthorizationStateWaitPhoneNumber ||
            r is td.AuthorizationStateWaitCode ||
            r is td.AuthorizationStateWaitPassword ||
            r is td.AuthorizationStateWaitOtherDeviceConfirmation ||
            r is td.AuthorizationStateReady) {
          return;
        }
      } on td.TdError catch (err) {
        _tdlog('TDLib web boot poll[$i] getAuthorizationState: ${err.message}');
      } on TimeoutException catch (e) {
        _tdlog('TDLib web boot poll[$i] $e');
      } catch (e) {
        _tdlog('TDLib web boot poll[$i] failed: $e');
      }
    }
    _tdlog('TDLib web boot poll: exhausted without reaching an interactive auth state');
  }

  Future<void> _pollQrLinkAfterRequest() async {
    td.AuthorizationState? lastAuth;
    for (var i = 0; i < 45; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_webJsAlive || _receivedTdlibFatal || _unsupportedAuthWire != null) {
        return;
      }
      if (_authPollPaused) {
        continue;
      }
      try {
        _tdlog('TDLib web QR poll[$i] → getAuthorizationState…');
        final r = await _sendAuthProbe(const td.GetAuthorizationState());
        if (r is td.AuthorizationStateWaitOtherDeviceConfirmation) {
          _tdlog('TDLib web QR poll[$i] → WaitOtherDeviceConfirmation (via getAuthorizationState)');
          _applyAuthorizationState(r);
          return;
        }
        if (r is td.AuthorizationState) {
          lastAuth = r;
          _tdlog('TDLib web QR poll[$i] state=${r.runtimeType}');
        }
      } on td.TdError catch (err) {
        _tdlog('TDLib web QR poll[$i] getAuthorizationState: ${err.message}');
      } on TimeoutException catch (e) {
        _tdlog('TDLib web QR poll[$i] $e');
      } catch (e) {
        _tdlog('TDLib web QR poll[$i] failed: $e');
      }
    }
    _tdlog('TDLib web QR poll: exhausted without WaitOtherDeviceConfirmation');
    final tail =
        lastAuth != null ? ' Last authorization state: ${lastAuth.runtimeType}.' : '';
    if (!_functionErrors.isClosed) {
      _functionErrors.add(
        'Telegram did not show a sign-in QR code.$tail '
        'Check your connection and try again.',
      );
    }
  }

  String _systemVersionSnippet() {
    try {
      final ua = window.navigator.userAgent;
      if (ua.length <= 120) return ua;
      return ua.substring(0, 120);
    } catch (_) {
      return 'web';
    }
  }

  void _handleTdError(td.TdError err) {
    if (_isIgnorableTdError(err)) {
      return;
    }

    if (_awaitingGetMeAfterReady) {
      _awaitingGetMeAfterReady = false;
      if (_isInteractiveAuthError(err)) {
        _failEnsureAuthorizedIfPending('GetMeError:${err.code}');
        unawaited(_invokeRequiresInteractiveLogin());
      } else {
        if (_getMeRetryCount < _kMaxGetMeRetries) {
          _getMeRetryCount += 1;
          Future<void>.delayed(const Duration(milliseconds: 350), _requestGetMe);
        } else if (!_authCompleter.isCompleted) {
          _authCompleter.completeError(err);
        }
      }
    }

    if (!_functionErrors.isClosed) {
      _functionErrors.add(err.message);
    }
  }

  bool _isIgnorableTdError(td.TdError err) {
    if (err.code == 406) return true;
    if (err.code == 400 && err.message.toLowerCase().contains("option can't be set")) {
      return true;
    }
    return false;
  }

  bool _isInteractiveAuthError(td.TdError err) {
    if (err.code == 401) return true;
    final message = err.message.toLowerCase();
    return message.contains('unauthorized') ||
        message.contains('not authorized') ||
        message.contains('authentication');
  }

  void _handleSessionUser(td.TdObject obj) {
    late final td.User user;
    if (obj is td.UpdateUser) {
      user = obj.user;
    } else if (obj is td.User) {
      user = obj;
    } else {
      return;
    }

    final byFallback = _awaitingGetMeAfterReady && user.id != 0;
    if (!byFallback) return;
    _awaitingGetMeAfterReady = false;
    authDebugSuccess('TDLib returned authenticated user details.');
    unawaited(_finalizeAuthenticatedSession(user));
  }

  Future<void> _finalizeAuthenticatedSession(td.User user) async {
    await _finalizeChain;
    final done = Completer<void>();
    _finalizeChain = done.future;
    try {
      if (_authCompleter.isCompleted) {
        return;
      }
      final onAuth = onUserAuthorized;
      try {
        if (onAuth != null) {
          await onAuth(user);
        }
        if (!_authUserId.isClosed) {
          _authUserId.add(user.id);
        }
        if (!_authCompleter.isCompleted) {
          _authCompleter.complete();
        }
      } catch (error) {
        if (!_functionErrors.isClosed) {
          _functionErrors.add('Could not save Telegram session: $error');
        }
        if (!_authCompleter.isCompleted) {
          _authCompleter.completeError(error);
        }
      }
    } finally {
      done.complete();
    }
  }

  void _handleAuthorization(td.TdObject obj) {
    if (obj is! td.UpdateAuthorizationState) return;
    _applyAuthorizationState(obj.authorizationState);
  }

  void _applyAuthorizationState(td.AuthorizationState state) {
    final wire = _pendingAuthStateWireType;
    _pendingAuthStateWireType = null;
    if (wire != null) {
      if (wire == 'authorizationStateWaitEncryptionKey') {
        _tdlog(
          'TDLib web: $wire — submitting checkDatabaseEncryptionKey '
          '(generated Dart API has no typed method for this step).',
        );
        unawaited(_submitDatabaseEncryptionKeyProbe());
        return;
      }
      _unsupportedAuthWire = wire;
      final hint = wire == 'authorizationStateWaitPremiumPurchase'
          ? 'Telegram is asking for a Premium purchase step before login. '
                'That authorization state is not represented in the generated API; use API credentials '
                'that do not trigger this flow.'
          : 'This TDLib WASM build reports "$wire", which the generated parser cannot map. '
                'Regenerate lib/td_api_generated to match tdweb.';
      if (!_functionErrors.isClosed) {
        _functionErrors.add('TDLib web: $hint');
      }
      _tdlog('TDLib web: unsupported authorization @type=$wire');
      return;
    }

    if (state is td.AuthorizationStateWaitTdlibParameters) {
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.info, 'TDLib auth state: WaitTdlibParameters.');
      if (_paramsSent || !_webJsAlive) return;
      final apiId = _pendingApiId;
      final apiHash = _pendingApiHash;
      if (apiId == null || apiHash == null) return;
      _paramsSent = true;
      _authPollPaused = true;
      const encKey = '';
      _databaseEncryptionKeyApplied = encKey;
      _enginePost(
        td.SetTdlibParameters(
          useTestDc: false,
          databaseDirectory: '',
          filesDirectory: '',
          databaseEncryptionKey: encKey,
          useFileDatabase: true,
          useChatInfoDatabase: true,
          useMessageDatabase: true,
          useSecretChats: false, // unsupported on tdweb WASM; worker may still align flags
          apiId: apiId,
          apiHash: apiHash,
          systemLanguageCode: 'en',
          deviceModel: 'OXPlayer Web',
          systemVersion: _systemVersionSnippet(),
          applicationVersion: '1.0.0',
        ),
      );
      return;
    }

    _authPollPaused = false;

    if (state is td.AuthorizationStateWaitPhoneNumber) {
      _hasReachedAuthorizationWaitPhoneNumber = true;
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.info, 'TDLib auth state: WaitPhoneNumber.');
      _failEnsureAuthorizedIfPending('WaitPhoneNumber');
      unawaited(_invokeRequiresInteractiveLogin());
      if (!_authWaitPhoneNumber.isClosed) {
        _authWaitPhoneNumber.add(true);
      }
      if (!_smsCodeChallenge.isClosed) {
        _smsCodeChallenge.add(null);
      }
    } else if (state is td.AuthorizationStateWaitCode) {
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.info, 'TDLib auth state: WaitCode.');
      _failEnsureAuthorizedIfPending('WaitCode');
      unawaited(_invokeRequiresInteractiveLogin());
      if (!_authWaitPhoneNumber.isClosed) {
        _authWaitPhoneNumber.add(false);
      }
      if (!_qrPayload.isClosed) {
        _qrPayload.add(null);
      }
      if (!_cloudPassword.isClosed) {
        _cloudPassword.add(null);
      }
      if (!_smsCodeChallenge.isClosed) {
        final info = state.codeInfo;
        _smsCodeChallenge.add(
          TdlibSmsCodeChallenge(
            phoneNumber: info.phoneNumber,
            resendTimeoutSeconds: info.timeout,
          ),
        );
      }
    } else if (state is td.AuthorizationStateWaitOtherDeviceConfirmation) {
      authDebugDedup(
        'tdlib_auth_state',
        AuthDebugLevel.info,
        'TDLib auth state: WaitOtherDeviceConfirmation (QR ready).',
      );
      _failEnsureAuthorizedIfPending('WaitOtherDeviceConfirmation');
      unawaited(_invokeRequiresInteractiveLogin());
      if (!_authWaitPhoneNumber.isClosed) {
        _authWaitPhoneNumber.add(false);
      }
      if (!_smsCodeChallenge.isClosed) {
        _smsCodeChallenge.add(null);
      }
      if (!_cloudPassword.isClosed) {
        _cloudPassword.add(null);
      }
      if (!_qrPayload.isClosed) {
        final link = state.link;
        _tdlog(
          'TDLib web: publishing QR link (length=${link.length}, '
          'startsWith=${link.length > 20 ? link.substring(0, 20) : link})',
        );
        _qrPayload.add(link);
      }
    } else if (state is td.AuthorizationStateReady) {
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.success, 'TDLib auth state: Ready. Requesting GetMe...');
      if (_authCompleter.isCompleted) {
        _authCompleter = Completer<void>();
      }
      if (!_cloudPassword.isClosed) {
        _cloudPassword.add(null);
      }
      if (!_smsCodeChallenge.isClosed) {
        _smsCodeChallenge.add(null);
      }
      if (!_authWaitPhoneNumber.isClosed) {
        _authWaitPhoneNumber.add(false);
      }
      if (!_qrPayload.isClosed) {
        _qrPayload.add(null);
      }
      _getMeRetryCount = 0;
      _requestGetMe();
    } else if (state is td.AuthorizationStateWaitPassword) {
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.info, 'TDLib auth state: WaitPassword.');
      _failEnsureAuthorizedIfPending('WaitPassword');
      unawaited(_invokeRequiresInteractiveLogin());
      if (!_authWaitPhoneNumber.isClosed) {
        _authWaitPhoneNumber.add(false);
      }
      if (!_smsCodeChallenge.isClosed) {
        _smsCodeChallenge.add(null);
      }
      if (!_qrPayload.isClosed) {
        _qrPayload.add(null);
      }
      if (!_cloudPassword.isClosed) {
        _cloudPassword.add(TdlibCloudPasswordChallenge(hint: state.passwordHint));
      }
    } else if (state is td.AuthorizationStateClosed) {
      _hasReachedAuthorizationWaitPhoneNumber = false;
      authDebugDedup('tdlib_auth_state', AuthDebugLevel.error, 'TDLib auth state: Closed.');
      _failEnsureAuthorizedIfPending('AuthorizationStateClosed');
      final completer = _closeHandshakeCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void _requestGetMe() {
    _awaitingGetMeAfterReady = true;
    authDebugDedup('tdlib_get_me', AuthDebugLevel.info, 'TDLib requesting GetMe for authenticated user details.');
    unawaited(() async {
      try {
        final result = await send(const td.GetMe());
        if (result is! td.User) {
          _awaitingGetMeAfterReady = false;
          if (!_functionErrors.isClosed) {
            _functionErrors.add('TDLib GetMe returned ${result.runtimeType} instead of User.');
          }
          authDebugError('TDLib GetMe returned ${result.runtimeType} instead of User.');
          return;
        }
        if (!_awaitingGetMeAfterReady) {
          return;
        }
        _awaitingGetMeAfterReady = false;
        authDebugSuccess('TDLib returned authenticated user details.');
        await _finalizeAuthenticatedSession(result);
      } catch (error) {
        if (_isInteractiveAuthErrorObject(error)) {
          _awaitingGetMeAfterReady = false;
          _failEnsureAuthorizedIfPending('GetMeInteractiveError');
          unawaited(_invokeRequiresInteractiveLogin());
          authDebugError('TDLib GetMe requires interactive authentication again: $error');
          return;
        }
        if (_getMeRetryCount < _kMaxGetMeRetries) {
          _getMeRetryCount += 1;
          authDebugError('TDLib GetMe failed, retrying ($_getMeRetryCount/$_kMaxGetMeRetries): $error');
          Future<void>.delayed(const Duration(milliseconds: 350), _requestGetMe);
          return;
        }
        _awaitingGetMeAfterReady = false;
        if (!_functionErrors.isClosed) {
          _functionErrors.add('TDLib GetMe failed: $error');
        }
        authDebugError('TDLib GetMe failed after retries: $error');
        if (!_authCompleter.isCompleted) {
          _authCompleter.completeError(error);
        }
      }
    }());
  }

  bool _isInteractiveAuthErrorObject(Object error) {
    if (error is! td.TdError) return false;
    return _isInteractiveAuthError(error);
  }

  void _failEnsureAuthorizedIfPending(String reason) {
    if (_authCompleter.isCompleted) return;
    _tdlog('TDLib interactive login required: $reason');
    _authCompleter.completeError(const TdlibInteractiveLoginRequired());
  }

  Future<void> _invokeRequiresInteractiveLogin() async {
    final callback = onRequiresInteractiveLogin;
    if (callback == null) return;
    try {
      await callback();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('TDLib onRequiresInteractiveLogin error: $error\n$stackTrace');
      }
    }
  }

  /// One retry with a new [instanceName] / IndexedDB after WASM init fatals.
  Future<void> _recoverTdwebAfterInitFatal() async {
    final apiId = _pendingApiId;
    final apiHash = _pendingApiHash;
    if (apiId == null || apiHash == null) {
      _receivedTdlibFatal = true;
      return;
    }
    _tdlog(
      'TDLib web: init fatal — recreating tdweb client '
      '(epoch ${_webSessionEpoch + 1}, fresh IndexedDB)',
    );
    _receivedTdlibFatal = false;
    _paramsSent = false;
    _authPollPaused = false;
    _hasReachedAuthorizationWaitPhoneNumber = false;
    await _shutdownClient();
    _webSessionEpoch += 1;
    if (_authCompleter.isCompleted) {
      _authCompleter = Completer<void>();
    }
    _registerDartPushHandler();
    _webJsAlive = true;
    try {
      await _jsCreateClient();
      await _jsWaitTdwebInited();
      _singletonOwner = this;
      unawaited(_bootstrapAuthorizationStatePolling());
    } catch (e) {
      _receivedTdlibFatal = true;
      _webJsAlive = false;
      if (!_functionErrors.isClosed) {
        _functionErrors.add(
          'Telegram web client failed to restart after a TDLib error: $e. '
          'Clear site data for this origin and reload.',
        );
      }
      _tdlog('TDLib web recoverTdwebAfterInitFatal failed: $e');
    }
  }

  Future<void> _shutdownClient() async {
    if (!_webJsAlive) {
      await _jsCloseClient();
      if (identical(_singletonOwner, this)) {
        _singletonOwner = null;
      }
      return;
    }

    _closeHandshakeCompleter = Completer<void>();
    try {
      await _jsSendJson(jsonEncode(const td.Close().toJson()));
    } catch (_) {
      if (!(_closeHandshakeCompleter?.isCompleted ?? true)) {
        _closeHandshakeCompleter?.complete();
      }
    }
    try {
      await _closeHandshakeCompleter!.future.timeout(const Duration(seconds: 4));
    } catch (_) {}
    _closeHandshakeCompleter = null;

    await _jsCloseClient();

    _webJsAlive = false;
    _paramsSent = false;
    _hasReachedAuthorizationWaitPhoneNumber = false;
    _awaitingGetMeAfterReady = false;
    _getMeRetryCount = 0;
    _pendingApiId = null;
    _pendingApiHash = null;
    if (identical(_singletonOwner, this)) {
      _singletonOwner = null;
    }
  }

  @override
  Future<void> startQrLogin() async {
    if (!_webJsAlive) {
      throw StateError('Call init() before requesting QR login.');
    }
    _tdlog(
      'TDLib web → RequestQrCodeAuthentication '
      '(hasReachedWaitPhone=$_hasReachedAuthorizationWaitPhoneNumber)',
    );
    try {
      final ack = await send(
        const td.RequestQrCodeAuthentication(otherUserIds: []),
      ).timeout(const Duration(seconds: 25));
      _tdlog('TDLib web: RequestQrCodeAuthentication ack: ${ack.runtimeType}');
    } on td.TdError catch (e) {
      final msg = 'requestQrCodeAuthentication: ${e.message} (code ${e.code})';
      if (!_functionErrors.isClosed) {
        _functionErrors.add(msg);
      }
      _tdlog('TDLib web ERROR: $msg');
      rethrow;
    } on TimeoutException catch (e) {
      final fatalTail = _lastTdlibFatalDetail;
      final msg = _unsupportedAuthWire != null
          ? 'Telegram QR sign-in blocked at unsupported step "$_unsupportedAuthWire". '
                'Update the app or refresh and try again.'
          : _receivedTdlibFatal
              ? 'Telegram QR sign-in failed'
                    '${fatalTail != null && fatalTail.isNotEmpty ? ': $fatalTail' : ''}. '
                    'Refresh the page and try again.'
              : 'Telegram QR sign-in timed out: $e';
      if (!_functionErrors.isClosed) {
        _functionErrors.add(msg);
      }
      _tdlog('TDLib web ERROR: $msg');
      rethrow;
    }
    unawaited(_pollQrLinkAfterRequest());
  }

  @override
  Future<void> submitCloudPassword(String password) async {
    if (!_webJsAlive) {
      throw StateError('Call init() before submitting password.');
    }
    await send(td.CheckAuthenticationPassword(password: password));
  }

  @override
  Future<void> submitAuthenticationPhoneNumber(String phoneNumber) async {
    if (!_webJsAlive) {
      throw StateError('Call init() before submitting phone number.');
    }
    final normalized = phoneNumber.trim();
    if (normalized.isEmpty) return;
    _enginePost(td.SetAuthenticationPhoneNumber(phoneNumber: normalized));
  }

  @override
  Future<void> submitAuthenticationCode(String code) async {
    if (!_webJsAlive) {
      throw StateError('Call init() before submitting code.');
    }
    final normalized = code.trim();
    if (normalized.isEmpty) return;
    _enginePost(td.CheckAuthenticationCode(code: normalized));
  }

  @override
  Future<void> resetLocalSessionForQrLogin() async {
    _webSessionEpoch += 1;
    // Drop interactive auth hints immediately so the login UI does not snap back
    // to 2FA / code while [destroy] runs.
    if (!_cloudPassword.isClosed) {
      _cloudPassword.add(null);
    }
    if (!_smsCodeChallenge.isClosed) {
      _smsCodeChallenge.add(null);
    }
    if (!_qrPayload.isClosed) {
      _qrPayload.add(null);
    }
    if (_webJsAlive) {
      try {
        _tdlog('TDLib web resetLocalSessionForQrLogin → destroy (wipe partial login DB)');
        await send(const td.Destroy()).timeout(const Duration(seconds: 15));
      } catch (e) {
        _tdlog('TDLib web Destroy (continuing with close): $e');
      }
    }
    await forceDestroyAfterLogOut();
  }

  @override
  Future<void> restartPreservingSession() async {
    await _shutdownClient();
  }

  @override
  Future<void> forceDestroyAfterLogOut() async {
    await _shutdownClient();
    _paramsSent = false;
    _awaitingGetMeAfterReady = false;
    _getMeRetryCount = 0;
    _pendingApiId = null;
    _pendingApiHash = null;
  }

  @override
  Future<void> dispose() async {
    try {
      await _shutdownClient();
      if (identical(_webActiveFacade, this)) {
        _webActiveFacade = null;
      }
      await _updates.close();
      await _qrPayload.close();
      await _cloudPassword.close();
      await _smsCodeChallenge.close();
      await _authWaitPhoneNumber.close();
      await _authUserId.close();
      await _functionErrors.close();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('TDLib web dispose error: $error\n$stackTrace');
      }
    }
  }
}

Map<String, dynamic>? _tdObjectToJson(td.TdObject obj) {
  try {
    final encoded = jsonEncode(obj.toJson());
    return jsonDecode(encoded) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
