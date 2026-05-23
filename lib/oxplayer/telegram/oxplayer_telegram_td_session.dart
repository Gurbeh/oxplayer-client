import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td_api;

import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';

import 'oxplayer_tdlib_debug.dart';
import 'oxplayer_telegram_td_runtime.dart';
import 'tdlib_controller.dart'
    if (dart.library.html) 'tdlib_controller_web.dart'
    if (dart.library.js_interop) 'tdlib_controller_web.dart';
import 'tdlib_facade.dart';

String _describeTdSendFailure(Object e) {
  if (e is td_api.TdError) {
    return '${e.message} (code ${e.code})';
  }
  try {
    final dyn = e as dynamic;
    final m = dyn.message;
    if (m is String && m.isNotEmpty) {
      return m;
    }
  } catch (_) {}
  final s = e.toString();
  if (s.contains('[object Object]') || s.contains('LegacyJavaScriptObject')) {
    return 'Telegram request failed (open browser console for connection details).';
  }
  return s;
}

String _debugUrlKind(String? url) {
  final value = url?.trim() ?? '';
  if (value.isEmpty) return 'empty';
  final lower = value.toLowerCase();
  final uri = Uri.tryParse(value);
  final host = uri?.host.isNotEmpty == true ? uri!.host : 'unparsed';
  if (lower.startsWith('https://t.me/')) return 't.me host=$host len=${value.length}';
  if (lower.startsWith('https://')) return 'https host=$host len=${value.length}';
  return 'non_https len=${value.length}';
}

/// Resolves [botUser] to the private bot chat used for WebApp URL RPCs.
///
/// On web, [SearchPublicChat] already returns that chat; [CreatePrivateChat] can
/// crash tdweb with "memory access out of bounds".
Future<td_api.Chat> _resolveBotPrivateChatForWebApp(
  TelegramTdlibFacade td,
  String botUser,
) async {
  td_api.Chat? resolved;

  final res = await td.send(td_api.SearchPublicChat(username: botUser));
  if (res is td_api.Chat && res.type is td_api.ChatTypePrivate) {
    resolved = res;
  }

  if (resolved == null) {
    throw StateError('Cannot resolve BOT_USERNAME to a private chat with the bot.');
  }
  if (kIsWeb) {
    return resolved;
  }
  final botUserId = (resolved.type as td_api.ChatTypePrivate).userId;
  final privateChat = await td.send(
    td_api.CreatePrivateChat(userId: botUserId, force: false),
  );
  if (privateChat is! td_api.Chat) {
    throw StateError('Failed to create private chat with bot');
  }
  return privateChat;
}

const _kOxDeviceIdPrefsKey = 'oxplayer_td_device_id';

/// TDLib-backed Telegram login + the same backend `/auth/telegram` bridge as oxplayer-android.
final class OxplayerTelegramTdSession {
  OxplayerTelegramTdSession({TelegramTdlibFacade? tdlib}) : _td = tdlib ?? OxplayerTelegramTdRuntime.facade;

  final TelegramTdlibFacade _td;
  bool _clientInited = false;

  /// Dedupes concurrent [fetchSignedInitData] (e.g. duplicate [authenticatedUserId] events)
  /// so Telegram one-shot WebApp auth tokens are not consumed twice in parallel.
  Future<String>? _signedInitDataInFlight;

  TdlibFacade get td => _td;

  Stream<String?> get qrLoginPayload => _td.qrLoginPayload;

  Stream<TdlibCloudPasswordChallenge?> get cloudPasswordChallenge =>
      _td.cloudPasswordChallenge;

  Stream<TdlibSmsCodeChallenge?> get smsCodeChallenge => _td.smsCodeChallenge;

  Stream<bool> get authorizationWaitPhoneNumber =>
      _td.authorizationWaitPhoneNumber;

  Stream<int> get authenticatedUserId => _td.authenticatedUserId;

  Stream<String?> get functionErrors => _td.functionErrors;

  static Future<void> initPlugin() async {
    await TelegramTdlibFacade.initTdlibPlugin();
  }

  Future<void> initClient() async {
    await initPlugin();
    final apiId = int.tryParse(OxplayerEnv.telegramApiId ?? '') ?? 0;
    final apiHash = OxplayerEnv.telegramApiHash ?? '';
    if (apiId <= 0 || apiHash.isEmpty) {
      throw StateError(
        'Set TELEGRAM_API_ID and TELEGRAM_API_HASH in assets/env/default.env (or dart-define).',
      );
    }
    if (_clientInited) return;
    // [TelegramTdlibFacade] is a process-wide singleton. A second
    // [OxplayerTelegramTdSession] (bootstrap warm-up + Riverpod notifier) must not
    // call [init] again: [_performInit] shuts down the existing client first,
    // which emits AuthorizationStateClosed and can destabilize or crash the app.
    if (_td.isInitialized) {
      _clientInited = true;
      return;
    }
    await _td.init(apiId: apiId, apiHash: apiHash, sessionString: '');
    _clientInited = true;
  }

  /// Returns true when an on-disk TDLib session is already authorized.
  ///
  /// [ensureAuthorized] can otherwise block (e.g. 2FA password, slow GetMe) while the splash
  /// screen has no UI for that. Used only for a best-effort restore before falling back to HTTP.
  static const _kSilentRestoreMaxWait = Duration(seconds: 25);
  static const _kSilentRestoreFirstAttemptWait = Duration(seconds: 8);

  Future<bool> trySilentRestore() async {
    await initClient();
    try {
      await _td.ensureAuthorized().timeout(
        _kSilentRestoreMaxWait,
        onTimeout: () => throw TimeoutException('TDLib.ensureAuthorized', _kSilentRestoreMaxWait),
      );
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> trySilentRestoreWithRestart() async {
    await initClient();
    try {
      await _td.ensureAuthorized().timeout(
        _kSilentRestoreFirstAttemptWait,
        onTimeout: () => throw TimeoutException(
          'TDLib.ensureAuthorized first attempt',
          _kSilentRestoreFirstAttemptWait,
        ),
      );
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } on TimeoutException {
      authDebugError('silent restore timed out; restarting TDLib client once.');
      try {
        await _td.restartPreservingSession();
      } catch (e) {
        authDebugError('restartPreservingSession failed: $e');
      }
      _clientInited = false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return trySilentRestore();
    } catch (e) {
      authDebugError('silent restore failed; restarting TDLib client once: $e');
      try {
        await _td.restartPreservingSession();
      } catch (_) {}
      _clientInited = false;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return trySilentRestore();
    }
  }

  /// Starts the TDLib authorization machine (QR / phone). Completes when the user is signed in to Telegram.
  Future<void> beginTelegramAuthorization() async {
    await initClient();
    try {
      await _td.ensureAuthorized();
    } on TdlibInteractiveLoginRequired {
      await _td.authenticatedUserId.first;
    }
  }

  Future<void> startQrLogin() async {
    authDebugSuccess('startQrLogin: begin');
    await initClient();
    await _ensureFreshPhoneNumberGateForQrStart();
    await _waitForPhoneNumberState();
    authDebugSuccess('startQrLogin: posting RequestQrCodeAuthentication to TDLib');
    try {
      await _td.startQrLogin();
    } catch (e) {
      if (!_isStaleTelegramAuthTokenError(e)) rethrow;
      authDebugError(
        'startQrLogin: stale auth token (${e is td_api.TdError ? e.message : e}) — resetting once.',
      );
      await resetLocalSessionForQrLogin();
      await initClient();
      await _waitForPhoneNumberState();
      await _td.startQrLogin();
    }
  }

  static bool isPartialInteractiveAuthorizationState(td_api.AuthorizationState state) {
    return state is td_api.AuthorizationStateWaitPassword ||
        state is td_api.AuthorizationStateWaitCode ||
        state is td_api.AuthorizationStateWaitOtherDeviceConfirmation ||
        state is td_api.AuthorizationStateWaitEmailAddress ||
        state is td_api.AuthorizationStateWaitEmailCode ||
        state is td_api.AuthorizationStateWaitRegistration;
  }

  /// True when TDLib resumed a prior sign-in that still needs 2FA, SMS, QR confirm, etc.
  Future<bool> hasPartialInteractiveAuthorization() async {
    await initClient();
    try {
      final r = await _td
          .send(const td_api.GetAuthorizationState())
          .timeout(const Duration(seconds: 12));
      if (r is! td_api.AuthorizationState) return false;
      return isPartialInteractiveAuthorizationState(r);
    } catch (_) {
      return false;
    }
  }

  /// After a refresh, TDLib can resume mid-login (2FA, QR confirm). [RequestQrCodeAuthentication]
  /// is only valid from [td_api.AuthorizationStateWaitPhoneNumber]; clear local storage first.
  Future<void> abandonStaleInteractiveAuthIfNeeded() async {
    await initClient();
    final td_api.TdObject r;
    try {
      r = await _td
          .send(const td_api.GetAuthorizationState())
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return;
    }
    if (r is! td_api.AuthorizationState) return;
    if (!isPartialInteractiveAuthorizationState(r)) return;
    authDebugSuccess(
      'abandonStaleInteractiveAuthIfNeeded: clearing partial login (${r.runtimeType})',
    );
    await resetLocalSessionForQrLogin();
    await initClient();
  }

  Future<void> _ensureFreshPhoneNumberGateForQrStart() async {
    td_api.TdObject r;
    try {
      r = await _td
          .send(const td_api.GetAuthorizationState())
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return;
    }
    if (r is td_api.AuthorizationStateWaitPhoneNumber) return;
    if (r is td_api.AuthorizationStateWaitTdlibParameters) {
      await _waitForPhoneNumberState();
      return;
    }
    authDebugSuccess(
      'QR requires WaitPhoneNumber; saw ${r.runtimeType} — resetting local Telegram session.',
    );
    await resetLocalSessionForQrLogin();
    await initClient();
    await _waitForPhoneNumberState();
  }

  static bool _isStaleTelegramAuthTokenError(Object e) {
    final raw = e is td_api.TdError ? e.message : e.toString();
    final compact = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    return compact.contains('AUTH_TOKEN_ALREADY_ACCEPTED') ||
        compact.contains('AUTHTOKENALREADYACCEPTED') ||
        raw.toUpperCase().contains('ALREADY ACCEPTED');
  }

  Future<void> submitAuthenticationPhoneNumber(String phone) async {
    await _waitForPhoneNumberState();
    return _td.submitAuthenticationPhoneNumber(phone);
  }

  /// Waits until TDLib has observed [AuthorizationStateWaitPhoneNumber] for this client
  /// (see [TdlibFacade.hasReachedAuthorizationWaitPhoneNumber]), or until a timeout.
  ///
  /// On web, [authorizationWaitPhoneNumber] stream events can be missed while tdweb warms up;
  /// the controller also advances auth via `getAuthorizationState` polling.
  Future<void> _waitForPhoneNumberState() async {
    const step = Duration(milliseconds: 100);
    const maxWait = Duration(seconds: 16);
    final sw = Stopwatch()..start();
    if (_td.hasReachedAuthorizationWaitPhoneNumber) {
      authDebugSuccess(
        '_waitForPhoneNumberState: gate already open (${sw.elapsedMilliseconds}ms)',
      );
      return;
    }
    authDebugSuccess(
      '_waitForPhoneNumberState: polling hasReached (max ${maxWait.inSeconds}s)…',
    );
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      if (_td.hasReachedAuthorizationWaitPhoneNumber) {
        authDebugSuccess(
          '_waitForPhoneNumberState: gate open after ${sw.elapsedMilliseconds}ms',
        );
        return;
      }
      await Future<void>.delayed(step);
    }
    authDebugError(
      '_waitForPhoneNumberState: timeout after ${sw.elapsedMilliseconds}ms '
      '(hasReached=${_td.hasReachedAuthorizationWaitPhoneNumber}) — proceeding anyway',
    );
  }

  Future<void> submitAuthenticationCode(String code) =>
      _td.submitAuthenticationCode(code);

  Future<void> submitCloudPassword(String password) =>
      _td.submitCloudPassword(password);

  Future<void> resetLocalSessionForQrLogin() async {
    _clientInited = false;
    // Use forceDestroyAfterLogOut (kill isolate first, then destroy) to avoid
    // the native crash where tdJsonClientDestroy races with a 1-second
    // tdJsonClientReceive poll that is still in flight in the receive isolate.
    if (_td.isInitialized) {
      await _td.forceDestroyAfterLogOut();
    }
  }

  /// Signs out from Telegram by sending [LogOut] to revoke the device session
  /// on Telegram's servers. Then safely destroys the TDLib client by killing
  /// the receive isolate first (prevents the native tdJsonClientDestroy crash).
  Future<void> signOut() async {
    if (_td.isInitialized) {
      try {
        // Revoke server-side device session.
        await _td.send(const td_api.LogOut());
        // Brief delay so TDLib can process LogOut before we destroy.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      } catch (_) {
        // Ignore — session may already be invalid.
      }
      // Kill isolate first, wait for receive drain, then destroy safely.
      await _td.forceDestroyAfterLogOut();
    }
    _clientInited = false;
  }

  Future<void> dispose() => _td.dispose();

  /// Ensures TDLib is initialized and authorized (for library Telegram playback).
  static Future<bool> ensureReadyForPlayback() async {
    try {
      final s = OxplayerTelegramTdSession();
      await s.initClient();
      await s.td.ensureAuthorized();
      return true;
    } on TdlibInteractiveLoginRequired {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// TDLib [chatId] of the private chat with [OxplayerEnv.botUsername], or `null` if unconfigured
  /// or the bot could not be resolved (same resolution path as [fetchSignedInitData]).
  Future<int?> resolveMainBotPrivateChatId() async {
    try {
      await _td.ensureAuthorized();
    } catch (_) {
      return null;
    }
    final botUser = OxplayerEnv.botUsername;
    if (botUser == null || botUser.isEmpty) {
      return null;
    }
    final privateChat = await _resolveBotPrivateChatForWebApp(_td, botUser);
    return privateChat.id;
  }

  /// Same pipeline as oxplayer-android [DataRepository._fetchSignedInitData]: TDLib obtains signed WebApp initData.
  Future<String> fetchSignedInitData() async {
    final existing = _signedInitDataInFlight;
    if (existing != null) return existing;
    final created = _fetchSignedInitDataImpl();
    _signedInitDataInFlight = created;
    try {
      return await created;
    } finally {
      _signedInitDataInFlight = null;
    }
  }

  Future<String> _fetchSignedInitDataImpl() async {
    // Web + debug: short-circuit before any TDLib / WebApp RPC when a static
    // init-data override is present.  Placed here — before ensureAuthorized —
    // so an unconfigured bot (getMainWebApp / getWebAppUrl rejection) never
    // surfaces as an async error during local development.
    final entryDebugInitData = OxplayerEnv.telegramWebAppInitDataDebugOverride ?? '';
    oxDebugLog(
      'fetchSignedInitData.entry '
      'web=$kIsWeb debug=$kDebugMode dotenv=${OxplayerDotenv.isLoaded} '
      'debugInitDataLen=${entryDebugInitData.length}',
    );
    if (kIsWeb && kDebugMode) {
      if (entryDebugInitData.isNotEmpty) {
        oxEnvLog(
          'fetchSignedInitData [web/debug]: '
          'short-circuiting with OXPLAYER_DEBUG_TELEGRAM_INIT_DATA',
        );
        oxDebugLog('fetchSignedInitData.debugOverride hit before TDLib RPC');
        return entryDebugInitData;
      }
      oxDebugLog(
        'fetchSignedInitData.debugOverride missing/empty; continuing to TDLib WebApp URL flow',
      );
    }

    await _td.ensureAuthorized();
    final botUser = OxplayerEnv.botUsername;
    if (botUser == null || botUser.isEmpty) {
      throw StateError('BOT_USERNAME (or OXPLAYER_BOT_USERNAME) is not configured.');
    }

    final privateChat = await _resolveBotPrivateChatForWebApp(_td, botUser);
    final botUserId = (privateChat.type as td_api.ChatTypePrivate).userId;

    String? webAppUrl;
    td_api.TdError? shortNameError;
    td_api.TdError? fallbackUrlError;
    String? otherFailure;

    final shortName = OxplayerEnv.telegramWebAppShortName?.trim() ?? '';
    final hostedHttps = OxplayerEnv.telegramHostedWebAppHttpsUrl;
    final directWebAppUrl = OxplayerEnv.telegramWebAppUrl;
    final miniOpenLink = OxplayerEnv.telegramMiniAppOpenLink;

    oxDebugLog(
      'fetchSignedInitData.config '
      'bot=${botUser.isNotEmpty} shortName="$shortName" '
      'hostedHttps=${_debugUrlKind(hostedHttps)} '
      'direct=${_debugUrlKind(directWebAppUrl)} '
      'mini=${_debugUrlKind(miniOpenLink)}',
    );

    if (kIsWeb) {
      // Prefer [getWebAppLinkUrl] for `https://t.me/<bot>/<shortName>` Mini App links.
      // [getWebAppUrl] only accepts a URL that came from a WebApp button, not an arbitrary hosted URL.
      // [getMainWebApp] requires BotFather "Main Web App"; keep it as a secondary path on web.
      const params = td_api.WebAppOpenParameters(theme: null, applicationName: 'oxplayer');
      final webErrs = <String>[];
      Future<String?> sendWeb(td_api.TdFunction fn) async {
        oxDebugLog('fetchSignedInitData.webRpc.start ${fn.runtimeType}');
        try {
          final r = await _td.send(fn).timeout(const Duration(seconds: 25));
          if (r is td_api.HttpUrl) {
            oxDebugLog(
              'fetchSignedInitData.webRpc.ok ${fn.runtimeType} httpUrl=${_debugUrlKind(r.url)}',
            );
            return r.url;
          }
          if (r is td_api.MainWebApp) {
            final u = r.url.trim();
            if (u.isNotEmpty) {
              oxDebugLog(
                'fetchSignedInitData.webRpc.ok ${fn.runtimeType} mainWebApp=${_debugUrlKind(u)}',
              );
              return u;
            }
          }
          oxDebugLog(
            'fetchSignedInitData.webRpc.empty ${fn.runtimeType} result=${r.runtimeType}',
          );
        } on td_api.TdError catch (e) {
          oxDebugLog(
            'fetchSignedInitData.webRpc.tdError ${fn.runtimeType} code=${e.code} message="${e.message}"',
          );
          webErrs.add('${fn.runtimeType}: ${e.message} (${e.code})');
        } catch (e) {
          oxDebugLog(
            'fetchSignedInitData.webRpc.error ${fn.runtimeType} ${_describeTdSendFailure(e)}',
          );
          webErrs.add('${fn.runtimeType}: ${_describeTdSendFailure(e)}');
        }
        return null;
      }

      if (shortName.isNotEmpty) {
        webAppUrl = await sendWeb(
          td_api.GetWebAppLinkUrl(
            chatId: privateChat.id,
            botUserId: botUserId,
            webAppShortName: shortName,
            startParameter: '',
            allowWriteAccess: true,
            parameters: params,
          ),
        );
      }
      if (webAppUrl == null && hostedHttps != null && hostedHttps.isNotEmpty) {
        webAppUrl ??= await sendWeb(
          td_api.GetWebAppUrl(
            botUserId: botUserId,
            url: hostedHttps,
            parameters: params,
          ),
        );
      } else {
        oxDebugLog(
          'fetchSignedInitData.skip GetWebAppUrl: '
          'OXPLAYER_TELEGRAM_WEBAPP_URL is missing or is a t.me/non-https URL',
        );
      }
      if (shortName.isNotEmpty) {
        webAppUrl ??= await sendWeb(
          td_api.GetMainWebApp(
            chatId: privateChat.id,
            botUserId: botUserId,
            startParameter: shortName,
            parameters: params,
          ),
        );
      }
      webAppUrl ??= await sendWeb(
        td_api.GetMainWebApp(
          chatId: privateChat.id,
          botUserId: botUserId,
          startParameter: '',
          parameters: params,
        ),
      );
      if (webAppUrl == null && webErrs.isNotEmpty) {
        otherFailure = webErrs.join(' | ');
      }
    } else {
      // Native tdlib-json: [getWebAppLinkUrl] then [getWebAppUrl].
      if (shortName.isNotEmpty) {
        for (var attempt = 0; attempt < 2 && webAppUrl == null; attempt++) {
          try {
            final result = await _td.send(
              td_api.GetWebAppLinkUrl(
                chatId: privateChat.id,
                botUserId: botUserId,
                webAppShortName: shortName,
                startParameter: '',
                allowWriteAccess: true,
                parameters: const td_api.WebAppOpenParameters(
                  theme: null,
                  applicationName: 'oxplayer',
                ),
              ),
            );
            if (result is td_api.HttpUrl) {
              webAppUrl = result.url;
            }
          } catch (e) {
            if (attempt == 0 && _isStaleTelegramAuthTokenError(e)) {
              await Future<void>.delayed(const Duration(milliseconds: 450));
              continue;
            }
            if (e is td_api.TdError) {
              shortNameError = e;
            } else {
              otherFailure ??= _describeTdSendFailure(e);
            }
          }
        }
      }

      if (webAppUrl == null && hostedHttps != null && hostedHttps.isNotEmpty) {
        for (var attempt = 0; attempt < 2 && webAppUrl == null; attempt++) {
          try {
            final fallbackResult = await _td.send(
              td_api.GetWebAppUrl(
                botUserId: botUserId,
                url: hostedHttps,
                parameters: const td_api.WebAppOpenParameters(
                  theme: null,
                  applicationName: 'oxplayer',
                ),
              ),
            );
            if (fallbackResult is td_api.HttpUrl) {
              webAppUrl = fallbackResult.url;
            }
          } catch (e) {
            if (attempt == 0 && _isStaleTelegramAuthTokenError(e)) {
              await Future<void>.delayed(const Duration(milliseconds: 450));
              continue;
            }
            if (e is td_api.TdError) {
              fallbackUrlError = e;
            } else {
              otherFailure ??= _describeTdSendFailure(e);
            }
          }
        }
      }
    }

    if (webAppUrl == null) {
      final initDbg = OxplayerEnv.telegramWebAppInitDataDebugOverride;
      if (initDbg != null && initDbg.isNotEmpty) {
        oxEnvLog(
          'fetchSignedInitData: TDLib did not return a WebApp URL; '
          'using OXPLAYER_DEBUG_TELEGRAM_INIT_DATA (debug).',
        );
        return initDbg;
      }
      const webRetryHint =
          'On web, refresh the page and sign in to Telegram again.';
      final short = OxplayerEnv.telegramWebAppShortName?.trim() ?? '';
      final directUrl = OxplayerEnv.telegramWebAppUrl ?? '';
      final mini = OxplayerEnv.compactTelegramWireUrl(
        OxplayerEnv.telegramMiniAppOpenLink ?? '',
      );
      if (shortNameError != null || fallbackUrlError != null || otherFailure != null) {
        final b = StringBuffer('Cannot get WebApp URL from Telegram.');
        if (shortNameError != null) {
          b.write(
            ' GetWebAppLinkUrl: ${shortNameError.message} (code ${shortNameError.code}).',
          );
        }
        if (fallbackUrlError != null) {
          b.write(
            ' GetWebAppUrl: ${fallbackUrlError.message} (code ${fallbackUrlError.code}).',
          );
        }
        if (otherFailure != null) {
          b.write(' $otherFailure');
        }
        b.write(
          ' short_name="$short" mini="$mini" dotenv=${OxplayerDotenv.isLoaded}.',
        );
        if (kIsWeb) {
          b.write(' $webRetryHint');
        }
        throw StateError(b.toString());
      }
      throw StateError(
        'Cannot get WebApp URL from Telegram (no URL and no error). '
        'short_name="$short" direct_url_set=${directUrl.isNotEmpty} mini="$mini" '
        'hosted_https_set=${hostedHttps != null && hostedHttps.isNotEmpty} '
        'dotenv=${OxplayerDotenv.isLoaded}. Set OXPLAYER_TELEGRAM_WEBAPP_URL to your '
        'deployed https://… Mini App origin (not t.me) for GetWebAppUrl, or use '
        'pnpm flutter:web / --dart-define-from-file=dart_defines.dev.json.'
        '${kIsWeb ? ' $webRetryHint' : ''}',
      );
    }

    final initData = _extractTgWebAppData(webAppUrl);
    if (initData == null || initData.isEmpty) {
      final initDbg = OxplayerEnv.telegramWebAppInitDataDebugOverride;
      if (initDbg != null && initDbg.isNotEmpty) {
        oxEnvLog(
          'fetchSignedInitData: tgWebAppData missing in resolved URL; '
          'using OXPLAYER_DEBUG_TELEGRAM_INIT_DATA (debug).',
        );
        return initDbg;
      }
      throw StateError('tgWebAppData not found in WebApp URL from Telegram.');
    }
    return initData;
  }

  static String? _extractTgWebAppData(String webAppUrl) {
    final uri = Uri.tryParse(webAppUrl);
    if (uri == null) return null;
    final fromQuery = _extractQueryParamRaw(query: uri.query, key: 'tgWebAppData');
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final fragment = uri.fragment;
    if (fragment.isNotEmpty) {
      final queryFromFragment =
          fragment.contains('?') ? fragment.substring(fragment.indexOf('?') + 1) : fragment;
      final fromFragment =
          _extractQueryParamRaw(query: queryFromFragment, key: 'tgWebAppData');
      if (fromFragment != null && fromFragment.isNotEmpty) return fromFragment;
    }
    return null;
  }

  static String? _extractQueryParamRaw({required String query, required String key}) {
    if (query.isEmpty) return null;
    for (final pair in query.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final rawKey = eq >= 0 ? pair.substring(0, eq) : pair;
      final decodedKey = _decodeComponentSafe(rawKey);
      if (decodedKey != key) continue;
      final rawValue = eq >= 0 ? pair.substring(eq + 1) : '';
      return _decodeComponentSafe(rawValue);
    }
    return null;
  }

  static String _decodeComponentSafe(String input) {
    if (input.isEmpty) return input;
    try {
      return Uri.decodeComponent(input);
    } catch (_) {
      return input;
    }
  }

  static Future<({String deviceId, String? deviceName})> resolveDeviceIdentity({
    required String defaultDeviceName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var storedId = prefs.getString(_kOxDeviceIdPrefsKey)?.trim() ?? '';
    if (storedId.isEmpty) {
      storedId = _generateDeviceId();
      await prefs.setString(_kOxDeviceIdPrefsKey, storedId);
    }
    return (deviceId: storedId, deviceName: defaultDeviceName);
  }

  static String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'oxa-$hex';
  }

  Future<OxplayerTelegramAuthResponse> authenticateWithOxApi({
    required String deviceName,
  }) async {
    final apiBase = OxplayerEnv.apiBaseUrl;
    if (apiBase == null) {
      throw StateError('OXPLAYER_API_BASE_URL is not configured.');
    }
    final initData = await fetchSignedInitData();
    final identity = await resolveDeviceIdentity(defaultDeviceName: deviceName);
    final client = OxplayerTelegramAuthClient(apiBase: apiBase);
    return client.exchangeInitData(
      initData: initData,
      deviceId: identity.deviceId,
      deviceName: identity.deviceName,
    );
  }
}
