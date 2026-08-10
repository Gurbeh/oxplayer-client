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
        submitCode = lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_code'),
        submitPassword =
            lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_submit_password'),
        requestQr = lib.lookupFunction<Int32 Function(), int Function()>('ox_request_qr'),
        logout = lib.lookupFunction<Int32 Function(), int Function()>('ox_logout'),
        startPlayback = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>, Int64),
            Pointer<Utf8> Function(Pointer<Utf8>, int)>('ox_start_playback'),
        stopPlayback =
            lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ox_stop_playback'),
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
  final int Function(Pointer<Utf8>) submitCode;
  final int Function(Pointer<Utf8>) submitPassword;
  final int Function() requestQr;
  final int Function() logout;
  final Pointer<Utf8> Function(Pointer<Utf8>, int) startPlayback;
  final int Function(Pointer<Utf8>) stopPlayback;
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
    DynamicLibrary lib;
    try {
      lib = DynamicLibrary.open('oxtelegram.dll');
    } catch (_) {
      final exe = File(Platform.resolvedExecutable);
      lib = DynamicLibrary.open('${exe.parent.path}\\oxtelegram.dll');
    }
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
