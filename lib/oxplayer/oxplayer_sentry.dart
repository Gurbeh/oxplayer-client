import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/src/video_player_helper.g.dart';

abstract final class OxplayerSentry {
  static Future<void> init() async {
    await OxplayerDotenv.ensureLoaded();
    final dsn = OxplayerEnv.sentryDsn;
    if (dsn == null) return;

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
    );
  }

  static Future<bool> _isLeanBackTv() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      return await NativeVideoActivity().isLeanBackEnabled();
    } catch (_) {
      return false;
    }
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
