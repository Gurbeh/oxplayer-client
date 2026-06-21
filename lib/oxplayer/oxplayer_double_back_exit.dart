import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// Android/TV: first back shows a toast; second back within [window] exits the app.
abstract final class OxplayerDoubleBackExit {
  static const Duration window = Duration(seconds: 2);

  static DateTime? _lastPress;

  static bool get isActive => OxplayerEnv.isEnabled && !kIsWeb && Platform.isAndroid;

  /// When true, root [PopScope] must not pop on the first back press.
  static bool blocksRootPop() => isActive;

  /// Handles back on the home root tab. Returns true when the event was consumed.
  static bool handleRootBack(BuildContext context) {
    if (!isActive) return false;

    final now = DateTime.now();
    final last = _lastPress;
    if (last != null && now.difference(last) <= window) {
      _lastPress = null;
      SystemNavigator.pop();
      return true;
    }

    _lastPress = now;
    FladderSnack.show(
      context.localized.oxplayerPressBackAgainToExit,
      context: context,
      duration: window,
    );
    return true;
  }
}
