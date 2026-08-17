import 'dart:async';

import 'package:chopper/chopper.dart';

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

    final isBot = await OxplayerTdlibBridgeController.instance().isNativeSessionActuallyBot();
    final headers = Map<String, String>.from(chain.request.headers);
    headers[oxplayerReaderKindHeader] = isBot ? 'bot' : 'session';
    return chain.proceed(chain.request.copyWith(headers: headers));
  }
}
