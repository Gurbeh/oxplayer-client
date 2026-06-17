import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/bootstrap/app_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/services/ox_update_service.dart';

/// OXPlayer startup hooks — keep upstream `main.dart` thin.
abstract final class OxplayerBootstrap {
  static Future<void> beforeAppBootstrap(List<String> args) async {
    await OxplayerDotenv.ensureLoaded();
    if (!OxplayerConfig.isEnabled) return;
  }

  static Future<void> afterAppBootstrap(AppBootstrapResult result) async {
    if (!OxplayerConfig.isEnabled) return;
    if (kIsWeb || !Platform.isAndroid) return;

    await OxUpdateService.checkOnLaunch(
      sharedPreferences: result.sharedPreferences,
      currentVersion: result.applicationInfo.version,
    );
  }

  /// Wraps the app root so deferred update prompts can obtain a [BuildContext].
  static Widget wrapRoot(Widget child) {
    if (!OxplayerConfig.isEnabled) return child;
    if (kIsWeb || !Platform.isAndroid) return child;
    return OxUpdatePromptHost(child: child);
  }
}
