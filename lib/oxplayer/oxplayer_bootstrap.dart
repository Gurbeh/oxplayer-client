import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_auth_file_service.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_desktop_deep_link.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_sentry_user_sync.dart';
import 'package:fladder/oxplayer/services/ox_github_update_service.dart';
import 'package:fladder/oxplayer/services/ox_update_service.dart';
import 'package:fladder/util/custom_cache_manager.dart';
import 'package:fladder/util/deep_link_helper.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:protocol_handler/protocol_handler.dart';

/// OXPlayer startup hooks — keep upstream `main.dart` thin.
abstract final class OxplayerBootstrap {
  static Future<void> beforeAppBootstrap(List<String> args) async {
    await OxplayerDotenv.ensureLoaded();
    if (!OxplayerConfig.isEnabled) return;
    if (!kIsWeb && Platform.isWindows) {
      oxplayerRememberWindowsStartupArgs(args);
      await protocolHandler.register(kOxplayerDeepLinkScheme);
    }
    CustomCacheManager.instance = CacheManager(
      Config(
        CustomCacheManager.key,
        stalePeriod: const Duration(days: 3),
        maxNrOfCacheObjects: 256,
        fileService: OxplayerAuthFileService(),
      ),
    );
  }

  static Future<void> afterAppBootstrap(AppBootstrapResult result) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      await OxUpdateService.checkOnLaunch(
        sharedPreferences: result.sharedPreferences,
        currentVersion: result.applicationInfo.version,
        currentBuildNumber: result.applicationInfo.buildNumber,
      );
      return;
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await OxGitHubUpdateService.checkOnLaunch(
        sharedPreferences: result.sharedPreferences,
        currentVersion: result.applicationInfo.version,
      );
    }
  }

  /// Wraps the app root so deferred update prompts can obtain a [BuildContext].
  static Widget wrapRoot(Widget child) {
    if (!OxplayerConfig.isEnabled) return child;
    if (kIsWeb) return child;

    var wrapped = child;
    if (Platform.isAndroid ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux) {
      wrapped = OxUpdatePromptHost(child: wrapped);
    }
    return OxplayerSentryUserSync(child: wrapped);
  }
}
