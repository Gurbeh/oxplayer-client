import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_main_bot_login_api.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// Aligns native TDLib with who the API will copy into.
///
/// Bot-token OX users get copies in `@personalBot`. A leftover phone/QR session stays
/// `kind=ready`, so play waits 20s on the wrong account and retry PlaybackInfo returns 424.
Future<void> oxplayerEnsureTdlibMatchesOxUser(String? accessToken) async {
  final token = accessToken?.trim() ?? '';
  if (token.isEmpty) return;
  try {
    final userBot = await OxplayerMainBotLoginApi().fetchUserBotToken(accessToken: token);
    if (userBot == null) return;
    final controller = OxplayerTdlibBridgeController.instance();
    await controller.ensureConfigured();
    await controller.ensureBotTokenSession(userBot.token);
    _oxplayTdlibLog('delivery reader = personal bot @${userBot.username}');
  } catch (e) {
    _oxplayTdlibLog('ensure delivery reader failed: $e');
  }
}

void oxplayerClearPlaybackCacheOnAccountSwitch() {
  OxplayerPlaybackLinkCache.clearAll();
}

void _oxplayTdlibLog(String message) => debugPrint('$oxplayTdlibLogTag: $message');
