import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_delivery_api.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Single dedicated tag for the whole native-playback (TDLib) resolve path — filter logcat on
/// this to see just this flow: `adb logcat | grep OXPLAY_TDLIB`.
const oxplayTdlibLogTag = 'OXPLAY_TDLIB';

void _oxplayTdlibLog(String message) => debugPrint('$oxplayTdlibLogTag: $message');

/// Scheme of the PlaybackInfo MediaSource.Path built by the delivery path
/// (`stream.TelegramDeliveryURL`, oxplayer-be/apps/api/internal/stream/telegram_url.go):
/// `oxplayer-tg://{providerBotId}/{messageId}?loc={locator}`.
const oxplayerTelegramScheme = 'oxplayer-tg';

/// Detects that Path shape. Both ids are 0 on a cold play — the backend has not committed to a
/// sender yet — so a `0/0` authority is valid and must still match here.
///
/// Parses the URL directly rather than threading the structured `TelegramProviderBotId`/
/// `TelegramMessageId` PlaybackInfo fields through the MediaSource model — a real, cleaner
/// signature change deferred as a follow-up since this keeps the change contained to the resolver.
bool oxplayerIsTelegramProviderLink(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != oxplayerTelegramScheme) return false;
  if (int.tryParse(uri.host) == null) return false;
  if (uri.pathSegments.length != 1) return false;
  return int.tryParse(uri.pathSegments[0]) != null;
}

/// True for a resolved `tdlib-file://{fileId}` playback url — bytes served through ExoPlayer's
/// DataSource pipeline (OxRoutingDataSource -> TelegramFileDataSource), fed live from TDLib.
/// mpv/mdk have no concept of this scheme (it's not a real network protocol, just an internal
/// media3 DataSource routing key) and will silently do nothing with it — callers must force the
/// native (ExoPlayer) backend for this url regardless of the user's player preference.
bool oxplayerIsTdlibFileUrl(String? url) => url != null && url.startsWith('tdlib-file://');

/// True for a resolved TdlibHttpBridgeServer url (mpv/mdk path) — a plain http url on the
/// loopback address, which no other part of this app ever serves media from, so the host alone is
/// a safe, simple signal. mpv/mdk play this like any other network stream (no special player
/// forcing needed, unlike [oxplayerIsTdlibFileUrl]), but it still needs the same
/// stopPlaybackSession cleanup as the ExoPlayer path once playback ends — see
/// TdlibBridgeObject.stopPlaybackSession/onTelegramPlaybackEnded.
bool oxplayerIsTdlibHttpBridgeUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  return uri != null && (uri.host == '127.0.0.1' || uri.host == 'localhost');
}

/// True for a resolved stream_cb `gotdstream://{id}` playback url (Windows libmpv path — see
/// OxplayerTelegramStreamCb) — mpv reads this via direct C callbacks
/// (go/oxtelegram/cshared/stream_cb.go), not a real network protocol, so nothing else in the app
/// ever produces this scheme, making it as safe/simple a signal as the HTTP bridge host check.
bool oxplayerIsGotdStreamCbUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'gotdstream';
}

/// True for either Telegram direct-play transport mpv/mdk understands: the loopback HTTP bridge
/// or (Windows) the stream_cb protocol that replaced it there. Use this, not the two individual
/// checks, for playback-session lifecycle decisions (stop/cleanup, retry-timer suppression,
/// resume-seek handling) that must not silently miss one transport while only checking the other.
bool oxplayerIsTelegramDirectPlayUrl(String? url) =>
    oxplayerIsTdlibHttpBridgeUrl(url) || oxplayerIsGotdStreamCbUrl(url);

/// True for any resolved playback url whose validity dies with the native playback session that
/// minted it — all three transports, unlike [oxplayerIsTelegramDirectPlayUrl] which deliberately
/// covers only the two mpv/mdk understands.
///
/// None of these are durable locators: the id in them is a per-session counter
/// (TdlibBridgeObject.playbackIdCounter), and the bytes behind it come from a fileFetcher that is
/// torn down when playback ends. Caching one and replaying it later hands ExoPlayer/mpv a url whose
/// backing session no longer exists — the "No active TDLib session for playback" report from the
/// TV. Use this for cache-admission and session-teardown decisions; use
/// [oxplayerIsTelegramDirectPlayUrl] for the "can this backend play it directly" question, which
/// is a different one (see lib_mpv.dart's stream_cb/HTTP-bridge tuning).
bool oxplayerIsSessionBoundPlaybackUrl(String? url) =>
    oxplayerIsTdlibFileUrl(url) || oxplayerIsTelegramDirectPlayUrl(url);

/// One parsed `oxplayer-tg://{providerBotId}/{messageId}?loc={locator}` Path.
class OxplayerTelegramDeliveryPath {
  const OxplayerTelegramDeliveryPath({
    required this.providerBotId,
    required this.messageId,
    required this.locator,
  });

  /// Both 0 on a cold play — the backend round-robins across senders and may fail over
  /// mid-request, so it names none until the copy actually lands.
  final int providerBotId;
  final int messageId;
  final String locator;

  /// False for `oxplayer-tg://0/0` — copy may already be in the DM, but PlaybackInfo has not
  /// committed bot/message ids yet. Caching that Path poisons play for 2h.
  bool get isCommitted => providerBotId > 0 && messageId > 0;

  OxTdlibPlaybackSource toSource({bool preferHttpBridge = false}) => OxTdlibPlaybackSource(
        providerBotId: providerBotId,
        messageId: messageId,
        locator: locator,
        preferHttpBridge: preferHttpBridge,
      );
}

/// Parses a delivery Path. Returns null when [url] is not one — callers should have checked with
/// [oxplayerIsTelegramProviderLink] first.
OxplayerTelegramDeliveryPath? oxplayerParseTelegramDeliveryPath(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != oxplayerTelegramScheme || uri.pathSegments.length != 1) {
    return null;
  }
  final providerBotId = int.tryParse(uri.host);
  final messageId = int.tryParse(uri.pathSegments[0]);
  final locator = uri.queryParameters['loc'] ?? '';
  if (providerBotId == null || messageId == null || locator.isEmpty) return null;
  return OxplayerTelegramDeliveryPath(
    providerBotId: providerBotId,
    messageId: messageId,
    locator: locator,
  );
}

final Set<String> _tdlibPlayResolvingLocators = <String>{};

/// True while [oxplayerResolveTdlibPlaybackUrl] is waiting on this locator.
/// Prefetch must not [warmDelivery] the same locator — it steals the 0/0 waiter.
bool oxplayerTdlibPlayIsResolving(String locator) =>
    locator.isNotEmpty && _tdlibPlayResolvingLocators.contains(locator);

bool oxplayerTdlibPlayInProgress() => _tdlibPlayResolvingLocators.isNotEmpty;

/// Resolves a delivery Path to a playable uri (`tdlib-file://{fileId}`, or the loopback/stream_cb
/// url when [preferHttpBridge]) by starting a native download session. Requires an already
/// logged-in Telegram session — callers should check
/// OxplayerTdlibBridgeController.instance().state.kind == ready and prompt login otherwise
/// (OxplayerTdlibLoginPanel / OxplayerTdlibQrLoginPanel) before reaching this resolver.
Future<String> oxplayerResolveTdlibPlaybackUrl(String url, {bool preferHttpBridge = false}) async {
  final parsed = oxplayerParseTelegramDeliveryPath(url);
  if (parsed == null) {
    throw ArgumentError('not an $oxplayerTelegramScheme delivery path: $url');
  }
  _tdlibPlayResolvingLocators.add(parsed.locator);
  try {
    return await _oxplayerResolveTdlibPlaybackUrlInner(parsed, preferHttpBridge: preferHttpBridge);
  } finally {
    _tdlibPlayResolvingLocators.remove(parsed.locator);
  }
}

Future<String> _oxplayerResolveTdlibPlaybackUrlInner(
  OxplayerTelegramDeliveryPath parsed, {
  required bool preferHttpBridge,
}) async {
  final controller = OxplayerTdlibBridgeController.instance();
  await controller.armDeliveryWaiter(parsed.locator);

  var source = parsed.toSource(preferHttpBridge: preferHttpBridge);
  if (!parsed.isCommitted) {
    // Prefetch warmDelivery often consumes the incoming copy and records the ref
    // before play's 0/0 waiter sees it — then startPlaybackSession(0/0) times out
    // while Telegram already has the message. Prefer the recorded ref.
      final landed = await waitForTdlibDeliveryRef(
        controller,
        parsed.locator,
        timeout: const Duration(milliseconds: 400),
      );
    if (landed != null) {
      source = OxTdlibPlaybackSource(
        providerBotId: landed.providerBotId,
        messageId: landed.messageId,
        locator: parsed.locator,
        preferHttpBridge: preferHttpBridge,
      );
      _oxplayTdlibLog(
        'cold play using landed delivery providerBotId=${landed.providerBotId} '
        'messageId=${landed.messageId} locator=${parsed.locator}',
      );
    }
  }

  _oxplayTdlibLog(
    'startPlaybackSession providerBotId=${source.providerBotId} messageId=${source.messageId} '
    'preferHttpBridge=$preferHttpBridge locator=${parsed.locator}',
  );
  try {
    final session = await controller.startPlaybackSession(source);
    _oxplayTdlibLog('startPlaybackSession ok -> $session');
    await oxplayerReportTelegramDelivery(controller, locator: parsed.locator);
    return session;
  } catch (e) {
    _oxplayTdlibLog(
        'startPlaybackSession FAILED providerBotId=${source.providerBotId} messageId=${source.messageId} error=$e');
    if (oxplayerIsTelegramDmStaleError(e)) {
      _oxplayTdlibLog('delivery stale for ${parsed.locator} — forgetting server-side mapping');
      await OxplayerTelegramDeliveryApi.forget(locator: parsed.locator);
    }
    if (oxplayerIsTelegramDeliveryWaitTimeoutError(e)) {
      final landed = await controller.deliveryRefForLocator(parsed.locator);
      if (landed != null && landed.messageId > 0 && landed.providerBotId > 0) {
        _oxplayTdlibLog(
          'retry startPlaybackSession after 0/0 timeout providerBotId=${landed.providerBotId} '
          'messageId=${landed.messageId}',
        );
        final retry = await controller.startPlaybackSession(
          OxTdlibPlaybackSource(
            providerBotId: landed.providerBotId,
            messageId: landed.messageId,
            locator: parsed.locator,
            preferHttpBridge: preferHttpBridge,
          ),
        );
        _oxplayTdlibLog('startPlaybackSession retry ok -> $retry');
        await oxplayerReportTelegramDelivery(controller, locator: parsed.locator);
        return retry;
      }
    }
    rethrow;
  }
}

Future<OxTdlibDeliveryRef?> waitForTdlibDeliveryRef(
  OxplayerTdlibBridgeController controller,
  String locator, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final ref = await controller.deliveryRefForLocator(locator);
    if (ref != null && ref.messageId > 0 && ref.providerBotId > 0) {
      return ref;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return controller.deliveryRefForLocator(locator);
}

/// Reports where the native session actually read this file, so the NEXT play is answered from the
/// backend's delivery table with no Telegram copy at all.
///
/// Best-effort: a failure here costs one redundant copy next time, never a broken playback. Both
/// numbers have to come from the receiving side — private-chat message ids are numbered per side,
/// and the server does not know which of its round-robin senders actually won.
Future<void> oxplayerReportTelegramDelivery(
  OxplayerTdlibBridgeController controller, {
  required String locator,
}) async {
  if (locator.isEmpty) return;
  final ref = await controller.deliveryRefForLocator(locator);
  if (ref == null || ref.messageId <= 0 || ref.providerBotId <= 0) return;
  _oxplayTdlibLog(
      'reporting delivery locator=$locator messageId=${ref.messageId} providerBotId=${ref.providerBotId}');
  await OxplayerTelegramDeliveryApi.report(
    locator: locator,
    messageId: ref.messageId,
    providerBotId: ref.providerBotId,
  );
}

/// True when the native bridge reported that a remembered DM message id is no longer usable — it
/// was deleted, the chat was cleared, or it now holds a different file. Distinct from a network or
/// config failure: the fix is to forget the id and re-copy, not to show the user an error. The
/// marker string is minted in go/oxtelegram/resolve.go (dmStaleErrorMarker); it travels as text
/// because the error crosses the gomobile/cgo boundary, which flattens typed errors anyway.
bool oxplayerIsTelegramDmStaleError(Object error) {
  if (error is PlatformException) {
    return '${error.code} ${error.message ?? ''}'.contains('OX_DM_STALE');
  }
  return error.toString().contains('OX_DM_STALE');
}

/// Native 0/0 waiter never saw the copy — usually prefetch [warmDelivery] already recorded it.
bool oxplayerIsTelegramDeliveryWaitTimeoutError(Object error) {
  final text = error is PlatformException
      ? '${error.code} ${error.message ?? ''}'
      : error.toString();
  return text.contains('timed out waiting') && text.contains('to be delivered');
}

/// True when [error] looks like TDLib reporting the message/file is gone (deleted from the
/// channel, channel banned, etc.) rather than a transient/config problem. The backend's public-pool
/// copy TTL (see TELEGRAM_PUBLIC_PROVIDER_COPY_TTL_HOURS) exists to avoid this, but a message can
/// still get deleted before the TTL catches up — callers should force-repair PlaybackInfo (which
/// sends a brand new copyMessage) and retry once rather than surfacing this to the user.
bool oxplayerIsTdlibFileMissingError(Object error) {
  // A stale bot-mode DM id is the same situation with a different cause: the bytes we were told
  // about are not there any more, and a fresh PlaybackInfo (which re-copies) fixes it. The
  // resolver has already dropped the server-side mapping by the time this is consulted.
  if (oxplayerIsTelegramDmStaleError(error)) return true;
  if (error is! PlatformException) return false;
  final text = '${error.code} ${error.message ?? ''}'.toLowerCase();
  return text.contains('tdlibexception') ||
      text.contains('telegrammedianotfoundexception') ||
      text.contains('message not found') ||
      text.contains('message_id_invalid') ||
      text.contains('file_reference') ||
      text.contains('chat not found') ||
      text.contains('channel_invalid') ||
      text.contains('chat_id_invalid');
}
