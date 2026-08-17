import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Low-level bindings to oxtelegram.dll (gotd c-shared host).
final class OxTelegramNative {
  OxTelegramNative._(DynamicLibrary lib)
      : configure = lib.lookupFunction<
            Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<OxAuthSinkNative>>),
            int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<NativeFunction<OxAuthSinkNative>>)>(
          'ox_configure',
        ),
        lastError = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ox_last_error'),
        free = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('ox_free'),
        currentAuthKind =
            lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ox_current_auth_kind'),
        currentAuthQr = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ox_current_auth_qr'),
        currentAuthHint =
            lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ox_current_auth_hint'),
        currentAuthError =
            lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('ox_current_auth_error'),
        submitPhone = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_phone'),
        submitBotToken =
            lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_bot_token'),
        submitCode = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_code'),
        submitPassword =
            lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_password'),
        requestQr = lib.lookupFunction<Int32 Function(), int Function()>('ox_request_qr'),
        logout = lib.lookupFunction<Int32 Function(), int Function()>('ox_logout'),
        startPlayback = lib.lookupFunction<Pointer<Utf8> Function(Int64, Int64, Pointer<Utf8>),
            Pointer<Utf8> Function(int, int, Pointer<Utf8>)>('ox_start_playback'),
        stopPlayback =
            lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_stop_playback'),
        deliveryMessageIdForLocator = lib.lookupFunction<Int64 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
          'ox_delivery_message_id_for_locator',
        ),
        deliveryProviderBotIdForLocator =
            lib.lookupFunction<Int64 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
          'ox_delivery_provider_bot_id_for_locator',
        ),
        armDeliveryWaiter =
            lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('ox_arm_delivery_waiter'),
        warmDelivery = lib.lookupFunction<Int32 Function(Int64, Int64, Pointer<Utf8>),
            int Function(int, int, Pointer<Utf8>)>('ox_warm_delivery'),
        ensureProviderBotsReady = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>(
          'ox_ensure_provider_bots_ready',
        ),
        streamUriForCurrentPlayback = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'ox_stream_uri_for_current_playback',
        ),
        streamOpenFnAddress = lib.lookup<NativeFunction<OxStreamOpenFnNative>>('ox_stream_open_fn'),
        fetchWebApp = lib.lookupFunction<
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)>(
          'ox_fetch_webapp_init_data',
        );

  final int Function(
    int apiId,
    Pointer<Utf8> apiHash,
    Pointer<Utf8> sessionPath,
    Pointer<Utf8> cachePath,
    Pointer<NativeFunction<OxAuthSinkNative>> sink,
  ) configure;

  final Pointer<Utf8> Function() lastError;
  final void Function(Pointer<Utf8>) free;
  final Pointer<Utf8> Function() currentAuthKind;
  final Pointer<Utf8> Function() currentAuthQr;
  final Pointer<Utf8> Function() currentAuthHint;
  final Pointer<Utf8> Function() currentAuthError;
  final int Function(Pointer<Utf8>) submitPhone;
  final int Function(Pointer<Utf8>) submitBotToken;
  final int Function(Pointer<Utf8>) submitCode;
  final int Function(Pointer<Utf8>) submitPassword;
  final int Function() requestQr;
  final int Function() logout;
  /// (providerBotId, messageId, locator) — both ids are 0 on a cold play, where the locator alone
  /// identifies the delivery still in flight.
  final Pointer<Utf8> Function(int, int, Pointer<Utf8>) startPlayback;
  final int Function(Pointer<Utf8>) stopPlayback;

  /// The DM message id the current session read for a locator, or 0. Reported to the backend
  /// together with [deliveryProviderBotIdForLocator] so the next play of that file needs no
  /// Telegram copy — see OxplayerTelegramDeliveryApi.
  final int Function(Pointer<Utf8>) deliveryMessageIdForLocator;

  /// The delivery bot whose DM held that message, or 0.
  final int Function(Pointer<Utf8>) deliveryProviderBotIdForLocator;

  /// Registers interest in a locator before PlaybackInfo triggers the copy, so a delivery that
  /// lands mid-request is captured rather than raced for.
  final void Function(Pointer<Utf8>) armDeliveryWaiter;

  /// Resolves a delivery and remembers where it landed, without opening a download — warm-up.
  /// Returns 0 on success, like every other status export here.
  final int Function(int, int, Pointer<Utf8>) warmDelivery;

  /// Starts, mutes and archives every delivery sender. Takes the backend's
  /// `[{"id":..,"username":".."}]` JSON. Returns 0 on success.
  final int Function(Pointer<Utf8>) ensureProviderBotsReady;
  final Pointer<Utf8> Function() streamUriForCurrentPlayback;

  /// Address of the native ox_stream_open_fn — pass this directly as mpv_stream_cb_add_ro's
  /// open_fn argument (see OxplayerTelegramStreamCb.registerOn). Never called from Dart itself,
  /// so the declared signature only needs to be a valid NativeFunction type, not byte-accurate to
  /// mpv_stream_cb_open_ro_fn's real C signature (mpv_stream_cb_info* stays opaque here).
  final Pointer<NativeFunction<OxStreamOpenFnNative>> streamOpenFnAddress;
  final Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>) fetchWebApp;

  static OxTelegramNative? _instance;

  static OxTelegramNative instance() {
    final existing = _instance;
    if (existing != null) return existing;
    if (!Platform.isWindows) {
      throw UnsupportedError('oxtelegram.dll is Windows-only');
    }
    // Prefer the DLL next to the exe. Bare `oxtelegram.dll` follows Windows search
    // order (PATH / leftover install) and can bind an older export set.
    final besideExe = '${File(Platform.resolvedExecutable).parent.path}\\oxtelegram.dll';
    final DynamicLibrary lib = File(besideExe).existsSync()
        ? DynamicLibrary.open(besideExe)
        : DynamicLibrary.open('oxtelegram.dll');
    return _instance = OxTelegramNative._(lib);
  }

  String readCString(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    final s = p.toDartString();
    free(p);
    return s;
  }

  void throwIfFailed(int rc) {
    if (rc == 0) return;
    final msg = readCString(lastError());
    throw OxTelegramNativeException(msg.isEmpty ? 'oxtelegram error ($rc)' : msg);
  }
}

/// C typedef: void (*)(const char*, const char*, const char*, const char*)
typedef OxAuthSinkNative = Void Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
);

/// C typedef: int (*)(void*, char*, mpv_stream_cb_info*) — matches mpv_stream_cb_open_ro_fn's
/// shape closely enough for FFI's purposes (the third param stays an opaque `Pointer<Void>` here
/// since this signature is never called from Dart, only its address is taken).
typedef OxStreamOpenFnNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
);

class OxTelegramNativeException implements Exception {
  OxTelegramNativeException(this.message);
  final String message;
  @override
  String toString() => message;
}
