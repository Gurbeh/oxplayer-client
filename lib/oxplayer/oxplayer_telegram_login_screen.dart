import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_debug.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_auth_client.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_init_data.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:fladder/models/settings/arguments_model.dart';
import 'package:fladder/td_api_generated/td_api.dart' as td_api;

enum _OxLoginPane { hub, qr, phone }

/// Suffix for Telegram flood / rate limit ([code] 420 / 429).
String _floodWaitUserHint(String message, int? code) {
  if (code != 429 && code != 420) {
    return '';
  }
  var sec = 0;
  final retry = RegExp(r'retry after\s+(\d+)', caseSensitive: false).firstMatch(message);
  if (retry != null) {
    sec = int.tryParse(retry.group(1) ?? '') ?? 0;
  }
  if (sec <= 0) {
    final fw = RegExp(r'FLOOD_WAIT_(\d+)', caseSensitive: false).firstMatch(message);
    if (fw != null) {
      sec = int.tryParse(fw.group(1) ?? '') ?? 0;
    }
  }
  if (sec <= 0) {
    return ' — Telegram rate limit: stop retrying for a while (often 15–60+ minutes).';
  }
  if (sec <= 120) {
    return ' — wait ${sec}s, then retry.';
  }
  final min = (sec / 60).ceil();
  final h = sec ~/ 3600;
  if (h >= 1) {
    final remMin = ((sec % 3600) / 60).ceil();
    final parts = <String>['~${h}h'];
    if (remMin > 0) {
      parts.add('${remMin}m');
    }
    return ' — wait ${parts.join(' ')} (${sec}s), then retry.';
  }
  return ' — wait ~$min min (${sec}s), then retry.';
}

/// TDLib web can reject with JS objects whose [Object.toString] is `[object Object]`.
String _formatTelegramLoginError(Object e) {
  if (e is td_api.TdError) {
    final hint = _floodWaitUserHint(e.message, e.code);
    return '${e.message} (code ${e.code})$hint';
  }
  try {
    final dyn = e as dynamic;
    final m = dyn.message;
    final c = dyn.code;
    if (m is String && m.isNotEmpty) {
      final hint = _floodWaitUserHint(m, c is int ? c : null);
      if (c is int) {
        return '$m (code $c)$hint';
      }
      return '$m$hint';
    }
  } catch (_) {}
  final s = e.toString();
  if (s == '[object Object]') {
    return 'Request failed (see browser console for Telegram connection details).';
  }
  return s;
}

@RoutePage()
class OxplayerTelegramLoginScreen extends ConsumerStatefulWidget {
  const OxplayerTelegramLoginScreen({
    @QueryParam('tgWebAppData') this.tgWebAppData,
    super.key,
  });

  /// Legacy Mini App deep link (optional). TDLib login ignores this when unused.
  final String? tgWebAppData;

  @override
  ConsumerState<OxplayerTelegramLoginScreen> createState() =>
      _OxplayerTelegramLoginScreenState();
}

class _OxplayerTelegramLoginScreenState
    extends ConsumerState<OxplayerTelegramLoginScreen> {
  _OxLoginPane _pane = _OxLoginPane.hub;
  bool _bootstrapping = true;
  String? _bootstrapError;
  bool _busy = false;
  bool _handledRouteInitData = false;
  bool _backendBridgeDone = false;
  /// Prevents double [applyOxplayerTelegramAuthResponse] from TDLib + bootstrap paths.
  bool _tdToBackendInFlight = false;
  /// True after TDLib accepts credentials until OX backend exchange + navigation finish.
  bool _completingOxLogin = false;
  bool _tdListenersStarted = false;

  OxplayerTelegramTdSession? _tdSession;
  Future<void>? _authorizationAttempt;

  StreamSubscription<String?>? _qrSub;
  StreamSubscription<TdlibCloudPasswordChallenge?>? _cloudPasswordSub;
  StreamSubscription<TdlibSmsCodeChallenge?>? _smsCodeSub;
  StreamSubscription<bool>? _waitPhoneSub;
  StreamSubscription<int>? _authenticatedUserSub;
  StreamSubscription<String?>? _functionErrorSub;

  String? _qrPayload;
  TdlibCloudPasswordChallenge? _cloudPasswordChallenge;
  TdlibSmsCodeChallenge? _smsCodeChallenge;
  String? _flowError;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  final FocusNode _passwordFocusNode =
      FocusNode(debugLabel: 'oxTelegram2faPassword');
  final FocusNode _passwordVisibilityFocusNode =
      FocusNode(debugLabel: 'oxTelegram2faPasswordVisibility');
  final FocusNode _codeFocusNode = FocusNode(debugLabel: 'oxTelegramSmsCode');
  final FocusNode _phoneFocusNode = FocusNode(debugLabel: 'oxTelegramPhone');

  bool _passwordObscured = true;
  bool _passwordSubmitting = false;
  bool _phoneSubmitting = false;
  bool _codeSubmitting = false;

  Timer? _qrStallTimer;

  @override
  void initState() {
    super.initState();
    _tdSession = OxplayerTelegramTdSession();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    unawaited(_qrSub?.cancel());
    unawaited(_cloudPasswordSub?.cancel());
    unawaited(_smsCodeSub?.cancel());
    unawaited(_waitPhoneSub?.cancel());
    unawaited(_authenticatedUserSub?.cancel());
    unawaited(_functionErrorSub?.cancel());
    _qrStallTimer?.cancel();
    // Do not dispose [OxplayerTelegramTdSession]: it uses the process-wide TDLib
    // ([OxplayerTelegramTdRuntime.facade]). Disposing here ran after navigate to
    // [DashboardRoute] and closed TDLib, breaking Telegram media playback.
    _passwordFocusNode.dispose();
    _passwordVisibilityFocusNode.dispose();
    _codeFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Dismiss the IME (numeric/phone) so the next step can show the correct keyboard.
  void _dismissKeyboard() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _hideSoftKeyboardWithoutUnfocus();
  }

  void _hideSoftKeyboardWithoutUnfocus() {
    if (!mounted) return;
    try {
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
  }

  /// D-pad / TV remote–first targets ([NavigationMode.directional]): never steal focus
  /// with a blanket [unfocus] when moving into the 2FA password field — that breaks
  /// remote focus and IME attachment on many Android TV / embedded TV stacks.
  bool _prefersDirectionalRemoteNavigation(BuildContext context) {
    return MediaQuery.maybeNavigationModeOf(context) ==
        NavigationMode.directional;
  }

  void _prepareImeBeforePasswordStep() {
    if (!mounted) return;
    if (_prefersDirectionalRemoteNavigation(context)) {
      _hideSoftKeyboardWithoutUnfocus();
    } else {
      _dismissKeyboard();
    }
  }

  void _requestFocusOnNextFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
    });
  }

  void _startTdListenersOnce() {
    _tdListenersStarted = true;
    final s = _tdSession!;
    _qrSub = s.qrLoginPayload.listen((payload) {
      if (kDebugMode) {
        debugPrint(
          '[OX login] qrLoginPayload: '
          '${payload == null ? "null" : "len=${payload.length}"}',
        );
      }
      if (!mounted) return;
      setState(() {
        _qrPayload = payload;
        // QR code is ready — unblock the UI so the Back button can be tapped.
        if (payload != null && payload.isNotEmpty) {
          _busy = false;
          _qrStallTimer?.cancel();
          _qrStallTimer = null;
        }
      });
    });
    _cloudPasswordSub = s.cloudPasswordChallenge.listen((c) {
      if (!mounted) return;
      if (c != null) {
        _prepareImeBeforePasswordStep();
      }
      setState(() {
        _cloudPasswordChallenge = c;
        if (c != null) {
          _passwordObscured = true;
          // TDLib needs 2FA — leave code/phone panes for the password step.
          _codeSubmitting = false;
          _completingOxLogin = false;
        }
        // Cloud password is an interactive state — unblock the UI so the
        // Continue button can be tapped.
        if (c != null) _busy = false;
      });
      if (c != null) {
        _requestFocusOnNextFrame(_passwordFocusNode);
      }
    });
    _smsCodeSub = s.smsCodeChallenge.listen((c) {
      if (!mounted) return;
      setState(() {
        _smsCodeChallenge = c;
        // SMS code entry is interactive — unblock the UI.
        if (c != null) _busy = false;
      });
      if (c != null) {
        _requestFocusOnNextFrame(_codeFocusNode);
      }
    });
    _waitPhoneSub = s.authorizationWaitPhoneNumber.listen((waiting) {
      if (!mounted || _completingOxLogin || _tdToBackendInFlight) return;
      setState(() {
        // Phone number entry is interactive — unblock the UI.
        if (waiting) _busy = false;
      });
    });
    _authenticatedUserSub = s.authenticatedUserId.listen((id) {
      if (!mounted || id == 0 || _backendBridgeDone || _tdToBackendInFlight) {
        return;
      }
      unawaited(_bridgeTdToBackend());
    });
    _functionErrorSub = s.functionErrors.listen((message) {
      if (!mounted || message == null || message.isEmpty) return;
      FladderSnack.show(message, context: context);
    });
  }

  Future<void> _bridgeTdToBackend() async {
    if (_backendBridgeDone || _tdToBackendInFlight || !mounted || _tdSession == null) {
      return;
    }
    _tdToBackendInFlight = true;
    setState(() {
      _completingOxLogin = true;
      _busy = true;
      _codeSubmitting = false;
      _passwordSubmitting = false;
    });
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName =
          '${app.name} / ${defaultTargetPlatform.name}';
      final exchanged =
          await _tdSession!.authenticateWithOxApi(deviceName: deviceName);
      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);
      ref.read(lockScreenActiveProvider.notifier).update((s) => false);
      _backendBridgeDone = true;
      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _completingOxLogin = false);
        FladderSnack.show('$e', context: context);
      }
    } finally {
      _tdToBackendInFlight = false;
      if (mounted && !_backendBridgeDone) {
        setState(() {
          _busy = false;
          _completingOxLogin = false;
        });
      }
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });

    OxplayerEnv.debugLogApiResolution();
    final api = OxplayerEnv.apiBaseUrl;
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (api == null || media == null) {
      oxEnvLog(
        'OxplayerTelegramLoginScreen._bootstrap: MISSING api or media '
        '(api=$api media=$media).',
      );
      setState(() {
        _bootstrapping = false;
        _bootstrapError =
            'Build is missing API configuration. Set OXPLAYER_API_BASE or OXPLAYER_API_BASE_URL.';
      });
      return;
    }

    FladderConfig.baseUrl = media;

    try {
      await ref.read(authProvider.notifier).initModel(clearUserState: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;

    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    if (_tdSession != null) {
      try {
        await OxplayerTelegramTdSession.initPlugin();
        await _bootstrapTdSessionForLogin();
        _startTdListenersOnce();
        if (await _tdSession!.trySilentRestore()) {
          if (!mounted) return;
          setState(() => _bootstrapping = false);
          await _bridgeTdToBackend();
          return;
        }
      } catch (e) {
        oxEnvLog('OxplayerTelegramLoginScreen TDLib silent restore: $e');
      }
    }

    setState(() => _bootstrapping = false);

    final fromRoute = widget.tgWebAppData?.trim();
    if (!_handledRouteInitData &&
        fromRoute != null &&
        fromRoute.isNotEmpty) {
      _handledRouteInitData = true;
      await _completeSignInWithInitData(fromRoute);
    }
  }

  /// TDLib web init can fatal on corrupt IndexedDB; one local reset + retry before QR.
  Future<void> _bootstrapTdSessionForLogin() async {
    final session = _tdSession;
    if (session == null) return;
    try {
      await session.initClient();
      await session.abandonStaleInteractiveAuthIfNeeded();
    } catch (e) {
      if (!kIsWeb) rethrow;
      oxEnvLog('OxplayerTelegramLoginScreen TDLib init failed; resetting web session: $e');
      await session.resetLocalSessionForQrLogin();
      await session.initClient();
      await session.abandonStaleInteractiveAuthIfNeeded();
    }
  }

  Future<void> _completeGooglePlayReviewSignIn(
    String phoneNumber,
    String code,
  ) async {
    final apiBase = OxplayerEnv.apiBaseUrl;
    if (apiBase == null) {
      FladderSnack.show('Missing API configuration', context: context);
      return;
    }

    if (ref.read(authProvider).serverLoginModel == null) {
      FladderSnack.show('Connecting to server… try again in a moment.',
          context: context);
      await _bootstrap();
      return;
    }

    setState(() => _codeSubmitting = true);
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName = kIsWeb
          ? 'OXPlayer Web'
          : '${app.name} / ${defaultTargetPlatform.name}';

      final client = OxplayerTelegramAuthClient(apiBase: apiBase);
      final exchanged = await client.googlePlayReviewLogin(
        phoneNumber: phoneNumber,
        code: code,
        deviceName: deviceName,
      );

      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);

      ref.read(lockScreenActiveProvider.notifier).update((s) => false);

      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } on OxplayerTelegramAuthException catch (e) {
      if (mounted) FladderSnack.show(e.message, context: context);
    } catch (e) {
      if (mounted) FladderSnack.show('$e', context: context);
    } finally {
      if (mounted) setState(() => _codeSubmitting = false);
    }
  }

  /// Optional path: raw WebApp initData from a deep link (same backend exchange).
  Future<void> _completeSignInWithInitData(String rawInitData) async {
    final apiBase = OxplayerEnv.apiBaseUrl;
    if (apiBase == null) {
      FladderSnack.show('Missing API configuration', context: context);
      return;
    }

    final initData = oxplayerNormalizeTelegramInitDataInput(rawInitData);
    if (initData.isEmpty) {
      FladderSnack.show('Telegram session not ready yet', context: context);
      return;
    }

    if (ref.read(authProvider).serverLoginModel == null) {
      FladderSnack.show('Connecting to server… try again in a moment.',
          context: context);
      await _bootstrap();
      return;
    }

    setState(() => _busy = true);
    try {
      final app = ref.read(applicationInfoProvider);
      final deviceName = kIsWeb
          ? 'OXPlayer Web'
          : '${app.name} / ${defaultTargetPlatform.name}';

      final client = OxplayerTelegramAuthClient(apiBase: apiBase);
      final exchanged = await client.exchangeInitData(
        initData: initData,
        deviceName: deviceName,
      );

      await ref.read(authProvider.notifier).applyOxplayerTelegramAuthResponse(exchanged);

      ref.read(lockScreenActiveProvider.notifier).update((s) => false);

      if (mounted) {
        await context.router.replaceAll([const DashboardRoute()]);
      }
    } on OxplayerTelegramAuthException catch (e) {
      if (mounted) FladderSnack.show(e.message, context: context);
    } catch (e) {
      if (mounted) FladderSnack.show('$e', context: context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensureAuthorizationStarted() async {
    final session = _tdSession;
    if (session == null || _authorizationAttempt != null) return;

    setState(() {
      _busy = true;
      _flowError = null;
    });

    final attempt = session.beginTelegramAuthorization();
    _authorizationAttempt = attempt;
    attempt.catchError((Object error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _authorizationAttempt = null;
        _flowError = error.toString();
      });
    });
  }

  Future<void> _startQrAuthentication() async {
    if (_tdSession == null) {
      if (kDebugMode) debugPrint('[OX login] _startQrAuthentication: no TD session');
      return;
    }
    if (kDebugMode) {
      debugPrint('[OX login] _startQrAuthentication: tap (listenersStarted=$_tdListenersStarted)');
    }
    setState(() {
      _pane = _OxLoginPane.qr;
      _flowError = null;
    });
    try {
      await _ensureAuthorizationStarted();
      if (kDebugMode) {
        debugPrint('[OX login] _startQrAuthentication: ensureAuthorizationStarted scheduled');
      }
      await _tdSession!.startQrLogin();
      if (kDebugMode) {
        debugPrint('[OX login] _startQrAuthentication: startQrLogin completed');
      }
      if (!mounted) return;
      setState(() => _busy = false);
      _qrStallTimer?.cancel();
      _qrStallTimer = Timer(const Duration(seconds: 50), () {
        if (!mounted) return;
        if (_pane != _OxLoginPane.qr) return;
        if (_qrPayload != null && _qrPayload!.isNotEmpty) return;
        setState(() {
          _flowError =
              'Could not load the Telegram sign-in QR code. '
              'Check your connection and try again.';
        });
      });
    } catch (error) {
      _qrStallTimer?.cancel();
      _qrStallTimer = null;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _authorizationAttempt = null;
        _flowError = error.toString();
      });
    }
  }

  Future<void> _startPhoneAuthentication() async {
    if (_tdSession == null) {
      return;
    }
    setState(() {
      _pane = _OxLoginPane.phone;
      _flowError = null;
    });
    try {
      await _ensureAuthorizationStarted();
    } catch (error) {
      if (!mounted) return;
      setState(() => _flowError = error.toString());
    }
    // Clear busy so AbsorbPointer doesn't block the phone input field.
    // TDLib authorization continues in the background.
    if (mounted) {
      setState(() => _busy = false);
      _requestFocusOnNextFrame(_phoneFocusNode);
    }
  }

  Future<void> _submitPhoneNumber() async {
    final session = _tdSession;
    final phoneNumber = _phoneController.text.trim();
    if (session == null || phoneNumber.isEmpty || _phoneSubmitting) return;

    if (OxplayerEnv.isGooglePlayReviewPhone(phoneNumber)) {
      setState(() {
        _smsCodeChallenge = TdlibSmsCodeChallenge(
          phoneNumber: phoneNumber,
          resendTimeoutSeconds: 0,
        );
      });
      _requestFocusOnNextFrame(_codeFocusNode);
      return;
    }

    setState(() => _phoneSubmitting = true);
    try {
      await session.submitAuthenticationPhoneNumber(phoneNumber);
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: ${_formatTelegramLoginError(e)}', context: context);
      }
    } finally {
      if (mounted) {
        if (_prefersDirectionalRemoteNavigation(context)) {
          _hideSoftKeyboardWithoutUnfocus();
        } else {
          _dismissKeyboard();
        }
        setState(() => _phoneSubmitting = false);
      }
    }
  }

  Future<void> _submitCode() async {
    final session = _tdSession;
    final code = _codeController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    if (session == null || code.isEmpty || _codeSubmitting) return;

    if (OxplayerEnv.isGooglePlayReviewCredentials(phoneNumber, code)) {
      await _completeGooglePlayReviewSignIn(phoneNumber, code);
      return;
    }

    setState(() => _codeSubmitting = true);
    var codeAccepted = false;
    try {
      await session.submitAuthenticationCode(code);
      codeAccepted = true;
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: ${_formatTelegramLoginError(e)}', context: context);
      }
    } finally {
      if (mounted) {
        if (_prefersDirectionalRemoteNavigation(context)) {
          _hideSoftKeyboardWithoutUnfocus();
        } else {
          _dismissKeyboard();
        }
        if (!codeAccepted) {
          setState(() => _codeSubmitting = false);
        }
        // On success keep [_codeSubmitting] until 2FA UI or [_bridgeTdToBackend].
      }
    }
  }

  Future<void> _submitPassword() async {
    final session = _tdSession;
    final password = _passwordController.text;
    if (session == null || password.isEmpty || _passwordSubmitting) return;

    setState(() => _passwordSubmitting = true);
    var passwordAccepted = false;
    try {
      await session.submitCloudPassword(password);
      passwordAccepted = true;
    } catch (e) {
      if (mounted) {
        FladderSnack.show('Telegram: ${_formatTelegramLoginError(e)}', context: context);
      }
    } finally {
      if (mounted && !passwordAccepted) {
        setState(() => _passwordSubmitting = false);
      }
      // On success keep [_passwordSubmitting] until [_bridgeTdToBackend].
    }
  }

  Future<void> _resetTelegramFlow() async {
    final session = _tdSession;
    if (session == null) return;

    _qrStallTimer?.cancel();
    _qrStallTimer = null;

    _passwordController.clear();
    _phoneController.clear();
    _codeController.clear();

    setState(() {
      _busy = true; // block UI while old TDLib client is torn down
      _authorizationAttempt = null;
      _backendBridgeDone = false;
      _completingOxLogin = false;
      _codeSubmitting = false;
      _passwordSubmitting = false;
      _flowError = null;
      _qrPayload = null;
      _cloudPasswordChallenge = null;
      _smsCodeChallenge = null;
      _pane = _OxLoginPane.hub;
    });

    await session.resetLocalSessionForQrLogin();

    if (mounted) setState(() => _busy = false);
  }

  Widget _buildHub(BuildContext context) {
    final missingTdKeys = (OxplayerEnv.telegramApiId ?? '').trim().isEmpty ||
        (OxplayerEnv.telegramApiHash ?? '').trim().isEmpty;
    if (missingTdKeys) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Set TELEGRAM_API_ID and TELEGRAM_API_HASH in assets/env/default.env.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final isDesktop = MediaQuery.sizeOf(context).width > 700;

    final qrButtonPrimary = FilledButton.icon(
      onPressed: (_busy || _bootstrapping) ? null : () => unawaited(_startQrAuthentication()),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: const Icon(Icons.qr_code_2),
      label: const Text('Login with QR code'),
    );

    final qrButtonSecondary = TextButton.icon(
      onPressed: (_busy || _bootstrapping) ? null : () => unawaited(_startQrAuthentication()),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: const Icon(Icons.qr_code_2),
      label: const Text('Login with QR code'),
    );

    final phoneButtonPrimary = FilledButton.icon(
      onPressed: (_busy || _bootstrapping) ? null : () => unawaited(_startPhoneAuthentication()),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: const Icon(Icons.phone_iphone),
      label: const Text('Login with number'),
    );

    final phoneButtonSecondary = TextButton.icon(
      onPressed: (_busy || _bootstrapping) ? null : () => unawaited(_startPhoneAuthentication()),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      icon: const Icon(Icons.phone_iphone),
      label: const Text('Login with number'),
    );

    final Widget primaryAuthBtn = leanBackMode ? qrButtonPrimary : phoneButtonPrimary;
    final Widget secondaryAuthBtn = leanBackMode ? phoneButtonSecondary : qrButtonSecondary;

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in with Telegram',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Scan a QR code in the Telegram app, or sign in with the phone number linked to your Telegram account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 20),
        primaryAuthBtn,
        const SizedBox(height: 12),
        secondaryAuthBtn,
        if (_flowError != null) ...[
          const SizedBox(height: 16),
          Text(
            _flowError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );

    const brandColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          child: FractionallySizedBox(
            widthFactor: 0.85,
            child: FittedBox(
              fit: BoxFit.contain,
              child: FladderLogo(),
            ),
          ),
        ),
      ],
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: Center(child: brandColumn)),
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: buttons,
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          brandColumn,
          const SizedBox(height: 40),
          buttons,
        ],
      ),
    );
  }

  Widget _buildQrPane(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide * 0.55;
    final qrSize = side.clamp(160.0, 280.0);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Scan this QR code with Telegram (Settings → Devices → Link Desktop Device) to sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        if (_flowError != null) ...[
          const SizedBox(height: 16),
          Text(
            _flowError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        if (_qrPayload != null && _qrPayload!.isNotEmpty)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: _qrPayload!,
                size: qrSize,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          )
        else
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _busy ? null : () => unawaited(_resetTelegramFlow()),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildPhoneStep(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the phone number linked to your Telegram account, '
              'in international format (e.g. +989123456789).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: TextField(
                focusNode: _phoneFocusNode,
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofocus: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Phone number',
                ),
                onSubmitted: (_) => unawaited(_submitPhoneNumber()),
              ),
            ),
            const SizedBox(height: 16),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: FilledButton(
                onPressed: _phoneSubmitting ? null : () => unawaited(_submitPhoneNumber()),
                child: _phoneSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send code'),
              ),
            ),
            const SizedBox(height: 12),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: OutlinedButton(
                onPressed: () => unawaited(_resetTelegramFlow()),
                child: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeStep(BuildContext context) {
    final challenge = _smsCodeChallenge;
    final isReviewCodeStep = OxplayerEnv.isGooglePlayReviewLoginConfigured &&
        OxplayerEnv.isGooglePlayReviewPhone(_phoneController.text.trim());
    final instruction = isReviewCodeStep
        ? 'Enter the review login code configured for this build.'
        : challenge == null || challenge.phoneNumber.isEmpty
            ? 'Enter the login code Telegram sent to your phone.'
            : 'Enter the login code Telegram sent to ${challenge.phoneNumber}.';

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              instruction,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: TextField(
                focusNode: _codeFocusNode,
                controller: _codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofocus: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Login code',
                ),
                onSubmitted: (_) => unawaited(_submitCode()),
              ),
            ),
            const SizedBox(height: 16),
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: FilledButton(
                onPressed: _codeSubmitting ? null : () => unawaited(_submitCode()),
                child: _codeSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm code'),
              ),
            ),
            const SizedBox(height: 12),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: OutlinedButton(
                onPressed: () => unawaited(_resetTelegramFlow()),
                child: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordStep(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This account uses two-step verification. Enter your Telegram password.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            if (_cloudPasswordChallenge != null &&
                _cloudPasswordChallenge!.hint.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Hint: ${_cloudPasswordChallenge!.hint}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: TextField(
                      focusNode: _passwordFocusNode,
                      controller: _passwordController,
                      obscureText: _passwordObscured,
                      autofocus: false,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Password',
                      ),
                      onSubmitted: (_) => unawaited(_submitPassword()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: FocusButton(
                    focusNode: _passwordVisibilityFocusNode,
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _passwordObscured = !_passwordObscured),
                    child: Tooltip(
                      message: _passwordObscured ? 'Show password' : 'Hide password',
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          _passwordObscured ? Icons.visibility : Icons.visibility_off,
                          semanticLabel:
                              _passwordObscured ? 'Show password' : 'Hide password',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FocusTraversalOrder(
              order: const NumericFocusOrder(3),
              child: FilledButton(
                onPressed: _passwordSubmitting ? null : () => unawaited(_submitPassword()),
                child: _passwordSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ),
            const SizedBox(height: 12),
            FocusTraversalOrder(
              order: const NumericFocusOrder(4),
              child: OutlinedButton(
                onPressed: () => unawaited(_resetTelegramFlow()),
                child: const Text('Back'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressState({required bool signingIn, bool verifying = false}) {
    final message = signingIn
        ? 'Signing in…'
        : verifying
            ? 'Verifying with Telegram…'
            : 'Waiting for Telegram authentication…';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildAuthContent(BuildContext context, {required double qrSize}) {
    // Only after TDLib auth is done (no further 2FA) — OX backend exchange.
    final showCompleting = _completingOxLogin || _tdToBackendInFlight;
    // Brief gap after SMS code accepted, before 2FA or backend bridge.
    final showPostCodePending = _codeSubmitting &&
        !showCompleting &&
        _cloudPasswordChallenge == null;
    final showPostPasswordPending = _passwordSubmitting &&
        !showCompleting &&
        _cloudPasswordChallenge == null;
    final showQr = !showCompleting &&
        !showPostCodePending &&
        !showPostPasswordPending &&
        _cloudPasswordChallenge == null &&
        _smsCodeChallenge == null &&
        _qrPayload != null &&
        _qrPayload!.isNotEmpty &&
        _pane == _OxLoginPane.qr;
    final showCode = !showCompleting &&
        !showPostCodePending &&
        _cloudPasswordChallenge == null &&
        _smsCodeChallenge != null;
    // Show the phone input as soon as the user picks that pane — don't wait
    // for TDLib's WaitPhoneNumber event (which causes a loading-spinner gap).
    final showPhone = !showCompleting &&
        !showPostCodePending &&
        !showPostPasswordPending &&
        _cloudPasswordChallenge == null &&
        _smsCodeChallenge == null &&
        !showQr &&
        _pane == _OxLoginPane.phone;
    final showProgress = (_busy || showCompleting) &&
        !showQr &&
        !showCode &&
        !showPhone &&
        !showPostCodePending &&
        !showPostPasswordPending &&
        _cloudPasswordChallenge == null;

    if (_cloudPasswordChallenge != null) {
      return _buildPasswordStep(context);
    }
    if (showCompleting) {
      return _buildProgressState(signingIn: true);
    }
    if (showPostCodePending || showPostPasswordPending) {
      return _buildProgressState(signingIn: false, verifying: true);
    }
    if (showQr) {
      return _buildQrPane(context);
    }
    if (showCode) {
      return _buildCodeStep(context);
    }
    if (showPhone) {
      return _buildPhoneStep(context);
    }
    if (_pane == _OxLoginPane.qr) {
      return _buildQrPane(context);
    }
    if (showProgress) {
      return _buildProgressState(signingIn: false);
    }
    return _buildHub(context);
  }

  @override
  Widget build(BuildContext context) {
    final authLoading = ref.watch(authProvider.select((s) => s.loading));

    Widget body;
    if (_bootstrapping || authLoading) {
      body = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Connecting…',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    } else if (_bootstrapError != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _bootstrapError!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _bootstrap(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      final isDesktop = MediaQuery.sizeOf(context).width > 700;
      final qrSize = isDesktop ? 300.0 : 220.0;
      body = _buildAuthContent(context, qrSize: qrSize);
    }

    final showBack = !_bootstrapping &&
        _bootstrapError == null &&
        (_pane != _OxLoginPane.hub || _flowError != null);

    return NotificationManagerInitializer(
      child: Scaffold(
        appBar: showBack
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _busy
                      ? null
                      : () {
                          if (_pane != _OxLoginPane.hub) {
                            unawaited(_resetTelegramFlow());
                          } else {
                            setState(() => _flowError = null);
                          }
                        },
                ),
              )
            : null,
        body: AbsorbPointer(
          absorbing: _busy,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              padding: const EdgeInsets.all(24),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
