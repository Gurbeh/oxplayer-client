import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_main_bot_login_api.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';
import 'package:fladder/src/tdlib_bridge.g.dart' show OxTdlibAuthStateKind;

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

/// Confirms THIS device's native Telegram session is still a usable identity for the signed-in OX
/// account, provisioning bot-mode on a fresh device that has no session yet.
///
/// The backend no longer has one "correct" reader per account — apps/api's resolveTelegramDelivery
/// now picks per REQUEST from readerKindHeader (see OxplayerReaderKindInterceptor), because the
/// same account is routinely used from multiple devices in different modes at once: e.g. a phone
/// that did QR login (session) and an older TV that only ever ran /connectbot (bot). Both are
/// valid simultaneously. So this no longer compares native's mode against the account's "default"
/// — it only asks whether native's CURRENT identity (whatever it is) still exists for this
/// account:
///  - native is bot-mode: fine as long as the account still has a connected personal bot.
///  - native holds a real phone/QR session: always fine once linked — a session identity doesn't
///    stop being valid just because the account also has a bot connected elsewhere.
///  - native has no ready identity yet (fresh device): bootstrap bot-mode if the account has a
///    bot to provision (the only silent option — a real session needs interactive phone/QR/2FA).
///
/// Getting this wrong used to fail in two different directions on this exact multi-device
/// scenario: comparing against the account's default (session, since 2026-08-16's backend change)
/// flagged a device that was CORRECTLY running bot-mode as a mismatch and blocked every play on
/// it, even though the account's bot was still connected and the new per-request header would
/// have routed to it just fine.
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

  final controller = OxplayerTdlibBridgeController.instance();

  if (controller.state.kind == OxTdlibAuthStateKind.ready) {
    // Ground truth from native, not the Dart-tracked flag: a bot session silently restored from
    // disk at this run's configure() never set that flag — see isNativeSessionActuallyBot's doc.
    if (await controller.isNativeSessionActuallyBot()) {
      if (userBot != null) return OxplayerReaderSyncResult.aligned;
      // A bot session can never read a DM that isn't its own (BOT_METHOD_INVALID on history, and
      // it is a different Telegram account entirely), and there is no cached credential to
      // silently switch back with — a real user login needs phone/code/2FA, unlike
      // submitBotToken's static secret. So a bot-mode device with no bot left on the account is a
      // hard mismatch, not a default-aligned case.
      _oxplayTdlibLog(
        'delivery reader MISMATCH: native session is still bot-mode but this OX account has no '
        'personal bot anymore — re-login required',
      );
      return OxplayerReaderSyncResult.mismatched;
    }
    // A real phone/QR session is always a valid identity once linked, independent of whether the
    // account also has a bot connected on some other device.
    return OxplayerReaderSyncResult.aligned;
  }

  // No ready identity on this device yet. Nothing to silently provision without a personal bot —
  // the caller's own ready-check surfaces the real "log in" prompt.
  if (userBot == null) return OxplayerReaderSyncResult.aligned;

  try {
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
