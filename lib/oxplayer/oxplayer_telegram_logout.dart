import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_delivery_reader_sync.dart';
import 'package:fladder/oxplayer/oxplayer_provider_bots_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';

/// Clears the on-device Telegram (gotd) session when the user signs out of OX.
/// OX [authProvider.logOutUser] alone leaves AuthReady — QR then fails with
/// `Cannot start QR login from state=ready`.
///
/// Does not re-warm Telegram here (that blocked logout UI for ~30s+). Login bootstrap
/// calls [OxplayerTdlibBridgeController.prepareForLoginScreen] afterward.
Future<void> oxplayerLogoutTelegramSession() async {
  if (!OxplayerConfig.isEnabled) return;
  OxplayerProviderBotsBootstrap.reset();
  oxplayerClearPlaybackCacheOnAccountSwitch();
  try {
    await OxplayerTdlibBridgeController.instance().clearSessionAfterOxLogout();
  } catch (e, st) {
    developer.log(
      'Telegram logout after OX sign-out failed: $e',
      name: 'ox-tdlib-auth',
      stackTrace: st,
    );
    if (kDebugMode) {
      debugPrint('[ox-tdlib-auth] Telegram logout after OX sign-out failed: $e');
    }
  }
}
