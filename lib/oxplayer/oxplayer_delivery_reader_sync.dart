import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_main_bot_login_api.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// Outcome of aligning the native Telegram session with the account the API copies into.
enum OxplayerReaderSyncResult {
  /// The native session reads the same inbox the API delivers to — either it already did, or the
  /// switch succeeded, or this OX user has no personal bot and the user session is correct.
  aligned,

  /// Could not determine which reader is required (the lookup call failed). The native session may
  /// well be correct; there is no evidence either way.
  unknown,

  /// A switch was required and failed. The native session is reading the WRONG inbox, so any
  /// playback started now waits on a copy that will never arrive there.
  mismatched,
}

/// Aligns the native Telegram session with who the API will copy into.
///
/// Bot-token OX users get copies in `@personalBot`. A leftover phone/QR session stays
/// `kind=ready`, so play waits 20s on the wrong account and retry PlaybackInfo returns 424.
///
/// Returns the outcome rather than throwing, and — importantly — rather than swallowing it. An
/// earlier version caught everything and logged, which let playback proceed on the wrong account
/// and present as a mysterious 20s stall. Callers on the play path must treat
/// [OxplayerReaderSyncResult.mismatched] as fatal; best-effort callers (prefetch, login panel) can
/// ignore the result, which is why this reports instead of deciding.
Future<OxplayerReaderSyncResult> oxplayerEnsureTdlibMatchesOxUser(String? accessToken) async {
  final token = accessToken?.trim() ?? '';
  if (token.isEmpty) return OxplayerReaderSyncResult.aligned;

  final OxplayerUserBotToken? userBot;
  try {
    userBot = await OxplayerMainBotLoginApi().fetchUserBotToken(accessToken: token);
  } catch (e) {
    // Only the lookup failed. The session in place may still be the right one, so this is
    // deliberately not reported as a mismatch — blocking every play on a transient API hiccup
    // would be worse than letting the existing 424/force-repair path handle a genuine miss.
    _oxplayTdlibLog('delivery reader lookup failed: $e');
    return OxplayerReaderSyncResult.unknown;
  }
  // No personal bot for this OX user: deliveries land in their own DM, which the user session
  // already reads — UNLESS this device's native session is still logged in as a leftover
  // personal bot from before the account's bot token was disconnected. A bot session can never
  // read a DM that isn't its own (BOT_METHOD_INVALID on history, and it is a different Telegram
  // account entirely), and there is no cached credential to silently switch back with — a real
  // user login needs phone/code/2FA, unlike submitBotToken's static secret. So this is a hard
  // mismatch, not a default-aligned case.
  if (userBot == null) {
    final controller = OxplayerTdlibBridgeController.instance();
    if (controller.nativeSessionIsBot) {
      _oxplayTdlibLog(
        'delivery reader MISMATCH: native session is still bot-mode but this OX account has no '
        'personal bot anymore — re-login required',
      );
      return OxplayerReaderSyncResult.mismatched;
    }
    return OxplayerReaderSyncResult.aligned;
  }

  try {
    final controller = OxplayerTdlibBridgeController.instance();
    await controller.ensureConfigured();
    await controller.ensureBotTokenSession(userBot.token);
    _oxplayTdlibLog('delivery reader = personal bot @${userBot.username}');
    return OxplayerReaderSyncResult.aligned;
  } catch (e) {
    _oxplayTdlibLog(
      'delivery reader MISMATCH: could not switch to personal bot @${userBot.username}: $e',
    );
    return OxplayerReaderSyncResult.mismatched;
  }
}

void oxplayerClearPlaybackCacheOnAccountSwitch() {
  OxplayerPlaybackLinkCache.clearAll();
}

void _oxplayTdlibLog(String message) => debugPrint('$oxplayTdlibLogTag: $message');
