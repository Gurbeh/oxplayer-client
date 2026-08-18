import 'dart:async';

import 'package:chopper/chopper.dart';

import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';

/// Declares which Telegram identity THIS device's native session is currently authenticated as,
/// on every PlaybackInfo request — see readerKindHeader's doc in apps/api's telegram_delivery.go
/// for why the backend needs this rather than deciding purely from account state.
///
/// An account used from two devices in different login modes (e.g. a phone that did QR login —
/// session — and an older TV that only ever ran /connectbot — bot) used to always get routed to
/// the SAME reader on both devices, because the backend had no way to tell them apart. The device
/// not matching that choice got copies delivered to a DM it could never read, and hung forever.
const oxplayerReaderKindHeader = 'X-OX-Reader-Kind';

/// Adds [oxplayerReaderKindHeader] to every PlaybackInfo POST, read fresh (ground truth, not a
/// cached flag — see isNativeSessionActuallyBot's doc) so it's still correct right after a
/// bot-token switch or a fresh QR login on this device.
class OxplayerReaderKindInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final path = chain.request.url.path.toLowerCase();
    if (!path.contains('playbackinfo')) {
      return chain.proceed(chain.request);
    }

    final headers = Map<String, String>.from(chain.request.headers);
    headers[oxplayerReaderKindHeader] = await _readerKind();
    return chain.proceed(chain.request.copyWith(headers: headers));
  }

  Future<String> _readerKind() async {
    final controller = OxplayerTdlibBridgeController.instance();
    if (await controller.isNativeSessionActuallyBot()) return 'bot';
    // Native may still be leftover QR after main-bot code login. Stored kind is this
    // device's identity — do not guess from a leftover cached bot token (a QR session
    // user who once ran /connectbot would then get copies in a DM they cannot read).
    final stored = await OxplayerOxLoginKindStore.readCurrent();
    if (stored == OxplayerOxLoginKind.bot) return 'bot';
    return 'session';
  }
}
