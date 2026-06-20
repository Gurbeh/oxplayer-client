import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/crash_log_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart';

abstract final class OxplayerSentry {
  static bool _handlersChained = false;

  /// Initializes Sentry and runs [appRunner] inside the SDK zone (required for async errors).
  static Future<void> init(Future<void> Function() appRunner) async {
    await OxplayerDotenv.ensureLoaded();
    final dsn = OxplayerEnv.sentryDsn;
    if (dsn == null) {
      await appRunner();
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final release = 'oxplayer-client@${packageInfo.version}+${packageInfo.buildNumber}';
    final leanBackTv = await _isLeanBackTv();

    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.release = release;
        options.dist = packageInfo.buildNumber;
        options.environment = OxplayerEnv.sentryEnvironment ?? (kReleaseMode ? 'production' : 'development');
        options.attachStacktrace = true;
        options.sendDefaultPii = false;
        // TCL / armeabi-v7a TVs crash in Sentry's native FileObserver thread (OXPLAYER-CLIENT-4/5).
        // Keep Dart error reporting; disable native NDK handler on leanback devices.
        if (leanBackTv) {
          options.enableNativeCrashHandling = false;
          options.enableNdkScopeSync = false;
        }
      },
      appRunner: appRunner,
    );
  }

  /// Re-wraps Flutter/platform error handlers after upstream [CrashLogNotifier] installs its own.
  /// Without this, local crash logs work but nothing is sent to Sentry.
  static void chainErrorHandlers() {
    if (!Sentry.isEnabled || _handlersChained) return;
    _handlersChained = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      unawaited(_captureFlutterError(details));
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = previousPlatformError?.call(error, stack) ?? false;
      unawaited(Sentry.captureException(error, stackTrace: stack));
      return handled;
    };
  }

  static Future<void> _captureFlutterError(FlutterErrorDetails details) async {
    await Sentry.captureException(details.exception, stackTrace: details.stack);
  }

  static Future<bool> _isLeanBackTv() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await NativeVideoActivity().isLeanBackEnabled();
    } catch (_) {
      return false;
    }
  }

  static Future<void> flushPersistedErrorLogs(CrashLogNotifier crashLog) async {
    await crashLog.ready;
    await crashLog.flushUnreportedToSentry();
  }

  static Future<void> sendTestMessage({String source = 'error_logs_hold'}) async {
    if (!Sentry.isEnabled) return;
    await Sentry.captureMessage(
      'OXPlayer client Sentry test',
      withScope: (scope) {
        scope
          ..setTag('source', source)
          ..setTag('test', 'true');
      },
    );
  }
}
