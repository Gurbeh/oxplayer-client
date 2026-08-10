import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_windows_ffi.dart';

/// C typedef: int (*)(mpv_handle*, const char*, void*, mpv_stream_cb_open_ro_fn)
typedef _MpvStreamCbAddRoNative = Int32 Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<NativeFunction<OxStreamOpenFnNative>>,
);
typedef _MpvStreamCbAddRoDart = int Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<NativeFunction<OxStreamOpenFnNative>>,
);

/// Registers the "gotdstream://" protocol (backed by oxtelegram.dll's stream_cb callbacks — see
/// go/oxtelegram/cshared/stream_cb.go) on one libmpv instance, so mpv reads Telegram bytes via
/// direct in-process callbacks instead of the loopback HTTP bridge.
///
/// mpv_stream_cb_add_ro is per mpv_handle, not process-global (see upstream stream_cb.h: "The
/// callback remains registered until the mpv core is [terminated]" — scoped to the instance it
/// was added to). Every place LibMPV creates a new mpv.Player needs its own call to
/// [registerOn] with that player's own handle: today that's `init()` and `crossfadeToUrl()`'s
/// `incomingPlayer` — missing either one leaves that specific player's `gotdstream://` loads
/// failing with MPV_ERROR_LOADING_FAILED while looking otherwise fine.
///
/// Registration itself (this file) is the same on Android and Windows — media_kit's `Player.handle`
/// and libmpv access work identically cross-platform via Dart FFI. What differs per platform is
/// only which native library exports `ox_stream_open_fn`: `oxtelegram.dll` on Windows,
/// `liboxtelegramstream.so` on Android (go/oxtelegram/cshared_android) — and, on Android, whether
/// the *caller* (TdlibBridgeObject.OX_TELEGRAM_STREAM_CB_ENABLED, currently off by default) even
/// hands out a `gotdstream://` uri yet, since that JNI-backed path is unvalidated on-device.
class OxplayerTelegramStreamCb {
  static const _protocol = 'gotdstream';
  static const _kMpvStreamCbAddRoSymbol = 'mpv_stream_cb_add_ro';
  static _MpvStreamCbAddRoDart? _addRo;
  static Pointer<NativeFunction<OxStreamOpenFnNative>>? _openFnAddress;

  static _MpvStreamCbAddRoDart _resolveMpvStreamCbAddRo() {
    final cached = _addRo;
    if (cached != null) return cached;
    DynamicLibrary? lib;
    // DynamicLibrary.process() resolves symbols against whatever is already mapped into this
    // process — critically, the *exact same* libmpv module media_kit itself loaded, not a
    // possibly-distinct module instance. Confirmed the hard way: reopening "libmpv-2.dll" by
    // bare name below returned mpv_stream_cb_add_ro, and it returned rc=0 (success) when called,
    // yet mpv's own stream layer reported the protocol as unregistered moments later — consistent
    // with that lookup and player.handle's ctx not agreeing on which loaded module is "the" mpv.
    // Keep the by-name candidates only as a fallback for platforms where .process() might not
    // resolve process-wide symbols the same way.
    try {
      lib = DynamicLibrary.process();
      lib.lookup(_kMpvStreamCbAddRoSymbol);
    } catch (_) {
      lib = null;
    }
    if (lib == null) {
      // Same candidate names/order media_kit's NativeLibrary.ensureInitialized tries.
      final candidates = Platform.isWindows
          ? const ['libmpv-2.dll', 'mpv-2.dll', 'mpv-1.dll']
          : const ['libmpv.so', 'libmpv.so.2', 'libmpv.so.1'];
      for (final name in candidates) {
        try {
          lib = DynamicLibrary.open(name);
          break;
        } catch (_) {
          continue;
        }
      }
    }
    if (lib == null) {
      throw StateError('OxplayerTelegramStreamCb: could not locate libmpv (expected already loaded by media_kit)');
    }
    final fn = lib.lookupFunction<_MpvStreamCbAddRoNative, _MpvStreamCbAddRoDart>(_kMpvStreamCbAddRoSymbol);
    _addRo = fn;
    return fn;
  }

  static Pointer<NativeFunction<OxStreamOpenFnNative>> _resolveOpenFnAddress() {
    final cached = _openFnAddress;
    if (cached != null) return cached;
    final Pointer<NativeFunction<OxStreamOpenFnNative>> address;
    if (Platform.isWindows) {
      address = OxTelegramNative.instance().streamOpenFnAddress;
    } else {
      // liboxtelegramstream.so is bundled under jniLibs/{abi}/ (see
      // go/oxtelegram/cshared_android/build.ps1) — Android's dynamic linker resolves the bare
      // name the same way System.loadLibrary would, no full path needed.
      final lib = DynamicLibrary.open('liboxtelegramstream.so');
      address = lib.lookup<NativeFunction<OxStreamOpenFnNative>>('ox_stream_open_fn');
    }
    _openFnAddress = address;
    return address;
  }

  /// Registers on the given raw mpv_handle address (from `player.handle`; see media_kit's
  /// `Player.handle`, backed by `ctx.address`). Safe to call more than once for the same handle: mpv
  /// returns MPV_ERROR_INVALID_PARAMETER (-4) for a protocol already registered on that instance,
  /// which this treats as expected, not a failure.
  static void registerOn(int mpvHandleAddress) {
    OxplayerStreamLog.event('stream_cb_register_attempt', fields: {
      'handle': mpvHandleAddress,
      'isWindows': Platform.isWindows,
      'isAndroid': Platform.isAndroid,
    });
    if (!Platform.isWindows && !Platform.isAndroid) return;
    try {
      final addRo = _resolveMpvStreamCbAddRo();
      final openFnAddress = _resolveOpenFnAddress();
      OxplayerStreamLog.event('stream_cb_register_resolved', fields: {
        'openFnAddress': openFnAddress.address,
      });
      final protocol = _protocol.toNativeUtf8();
      try {
        final rc = addRo(
          Pointer<Void>.fromAddress(mpvHandleAddress),
          protocol,
          nullptr,
          openFnAddress,
        );
        OxplayerStreamLog.event('stream_cb_register_result', fields: {'rc': rc});
        if (rc != 0 && rc != -4) {
          OxplayerStreamLog.event('stream_cb_register_failed', fields: {'rc': rc});
        }
      } finally {
        malloc.free(protocol);
      }
    } catch (error) {
      OxplayerStreamLog.event('stream_cb_register_error', fields: {'error': error.toString()});
    }
  }

  /// `gotdstream://{id}` for the currently active oxtelegram playback session, or null if none —
  /// mirrors oxplayerIsTdlibHttpBridgeUrl's role for the HTTP bridge path.
  static String? currentStreamUri() {
    if (!Platform.isWindows) return null;
    try {
      final native = OxTelegramNative.instance();
      final ptr = native.streamUriForCurrentPlayback();
      if (ptr == nullptr) return null;
      return native.readCString(ptr);
    } catch (_) {
      return null;
    }
  }
}
