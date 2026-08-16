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
/// Mirrors apps/api/internal/server/telegram_delivery.go's resolveDeliveryReader precedence
/// exactly: a linked Telegram session always wins over a connected personal bot, bot-token is
/// only the active reader for accounts with no session. That precedence is decided server-side
/// (auth_bot_token.go's readerKind, computed the same way resolveDeliveryReader picks) rather
/// than re-derived here, so the two can never drift apart again — they did once: this used to
/// force bot-mode purely on "does a personal bot exist", which was correct back when bot-token
/// was checked first server-side, and silently went wrong the moment that server-side precedence
/// flipped to session-first without a matching client change. A leftover phone/QR session stays
/// `kind=ready` while the backend copies into a bot the native side never reads (or vice versa),
/// so play waits the full delivery-wait timeout on the wrong account and retry PlaybackInfo
/// returns 424 — permanently, since there is no live push coming to the account it is watching.
///
/// Returns the outcome rather than throwing, and — importantly — rather than swallowing it. An
/// earlier version caught everything and logged, which let playback proceed on the wrong account
/// and present as a mysterious stall. Callers on the play path must treat
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

  // No personal bot for this OX user, or the backend prefers the linked session anyway: deliveries
  // land in the user's own DM, which a session-mode native bridge already reads — UNLESS this
  // device's native session is still logged in as a leftover personal bot (from before the bot
  // was disconnected, or from a stale switch this same sync forced under the old precedence). A
  // bot session can never read a DM that isn't its own (BOT_METHOD_INVALID on history, and it is a
  // different Telegram account entirely), and there is no cached credential to silently switch
  // back with — a real user login needs phone/code/2FA, unlike submitBotToken's static secret. So
  // that combination is a hard mismatch, not a default-aligned case.
  final wantsBot = userBot != null && !userBot.isSessionPreferred;
  if (!wantsBot) {
    final controller = OxplayerTdlibBridgeController.instance();
    if (controller.nativeSessionIsBot) {
      _oxplayTdlibLog(
        'delivery reader MISMATCH: native session is still bot-mode but the backend delivers to '
        'this account\'s Telegram session — re-login required',
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
