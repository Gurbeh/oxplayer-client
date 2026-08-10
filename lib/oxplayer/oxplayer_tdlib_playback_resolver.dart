import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Single dedicated tag for the whole native-playback (TDLib) resolve path — filter logcat on
/// this to see just this flow: `adb logcat | grep OXPLAY_TDLIB`.
const oxplayTdlibLogTag = 'OXPLAY_TDLIB';

void _oxplayTdlibLog(String message) => debugPrint('$oxplayTdlibLogTag: $message');

/// Detects a PlaybackInfo MediaSource.Path built by writePlaybackInfoOK's MTProto direct-play
/// branch (`stream.TelegramPublicLink`, oxplayer-be/apps/api/internal/stream/jwt.go):
/// `https://t.me/{channelUsername}/{messageId}`.
///
/// Parses the URL directly rather than threading the structured `TelegramChannelUsername`/
/// `TelegramMessageId` PlaybackInfo fields through the MediaSource model — a real, cleaner
/// signature change deferred as a follow-up (see plan doc C.3) since this keeps the change
/// contained to the resolver.
bool oxplayerIsTelegramProviderLink(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host != 't.me') return false;
  if (uri.pathSegments.length != 2) return false;
  return int.tryParse(uri.pathSegments[1]) != null;
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

/// Resolves a `t.me/{username}/{messageId}` PlaybackInfo link to a `tdlib-file://{fileId}` uri by
/// starting a TDLib download session (see TelegramFileDataSource on the Android side, which reads
/// from that uri). Requires an already-logged-in Telegram user session — callers should check
/// OxplayerTdlibBridgeController.instance().state.kind == ready and prompt login otherwise
/// (OxplayerTdlibLoginPanel / OxplayerTdlibQrLoginPanel) before reaching this resolver.
Future<String> oxplayerResolveTdlibPlaybackUrl(String url, {bool preferHttpBridge = false}) async {
  final uri = Uri.parse(url);
  final channelUsername = uri.pathSegments[0];
  final messageId = int.parse(uri.pathSegments[1]);
  _oxplayTdlibLog(
    'startPlaybackSession channel=$channelUsername messageId=$messageId preferHttpBridge=$preferHttpBridge',
  );
  final controller = OxplayerTdlibBridgeController.instance();
  try {
    final session = await controller.startPlaybackSession(
      OxTdlibPlaybackSource(
        channelUsername: channelUsername,
        messageId: messageId,
        preferHttpBridge: preferHttpBridge,
      ),
    );
    _oxplayTdlibLog('startPlaybackSession ok -> $session');
    return session;
  } catch (e) {
    _oxplayTdlibLog('startPlaybackSession FAILED channel=$channelUsername messageId=$messageId error=$e');
    rethrow;
  }
}

/// True when [error] looks like TDLib reporting the message/file is gone (deleted from the
/// channel, channel banned, etc.) rather than a transient/config problem. The backend's public-pool
/// copy TTL (see TELEGRAM_PUBLIC_PROVIDER_COPY_TTL_HOURS) exists to avoid this, but a message can
/// still get deleted before the TTL catches up — callers should force-repair PlaybackInfo (which
/// sends a brand new copyMessage) and retry once rather than surfacing this to the user.
bool oxplayerIsTdlibFileMissingError(Object error) {
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
