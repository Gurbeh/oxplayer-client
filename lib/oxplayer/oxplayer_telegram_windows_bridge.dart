import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/oxplayer/oxplayer_telegram_windows_ffi.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Windows gotd host implementing the same surface as Android Pigeon [OxTdlibBridgeApi].
class OxTelegramWindowsBridge {
  OxTelegramWindowsBridge({void Function(OxTdlibAuthState state)? onAuthStateChanged})
      : _onAuthStateChanged = onAuthStateChanged;

  final void Function(OxTdlibAuthState state)? _onAuthStateChanged;
  final _native = OxTelegramNative.instance();

  NativeCallable<OxAuthSinkNative>? _sinkCallable;
  OxTdlibAuthState _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
  bool _configured = false;

  OxTdlibAuthState get state => _state;

  Future<void> configure(int apiId, String apiHash) async {
    if (_configured) return;
    final support = await getApplicationSupportDirectory();
    final sessionPath = '${support.path}\\oxtelegram\\session.bin';
    final cachePath = '${support.path}\\oxtelegram\\cache';
    await Directory('${support.path}\\oxtelegram').create(recursive: true);

    _sinkCallable?.close();
    _sinkCallable = NativeCallable<OxAuthSinkNative>.listener(_handleAuthSink);

    final hashPtr = apiHash.toNativeUtf8();
    final sessPtr = sessionPath.toNativeUtf8();
    final cachePtr = cachePath.toNativeUtf8();
    try {
      final rc = _native.configure(
        apiId,
        hashPtr,
        sessPtr,
        cachePtr,
        _sinkCallable!.nativeFunction,
      );
      _native.throwIfFailed(rc);
      _configured = true;
      _state = currentAuthState();
      _onAuthStateChanged?.call(_state);
    } finally {
      malloc.free(hashPtr);
      malloc.free(sessPtr);
      malloc.free(cachePtr);
    }
  }

  void _handleAuthSink(
    Pointer<Utf8> kind,
    Pointer<Utf8> qr,
    Pointer<Utf8> hint,
    Pointer<Utf8> err,
  ) {
    // Native owns these CStrings for the duration of the callback only — copy immediately.
    final state = OxTdlibAuthState(
      kind: _kindFromString(kind.toDartString()),
      qrLoginUrl: _emptyToNull(qr.toDartString()),
      passwordHint: _emptyToNull(hint.toDartString()),
      errorMessage: _emptyToNull(err.toDartString()),
    );
    _state = state;
    _onAuthStateChanged?.call(state);
  }

  static String? _emptyToNull(String s) => s.isEmpty ? null : s;

  static OxTdlibAuthStateKind _kindFromString(String kind) {
    switch (kind) {
      case 'waitingForPhoneNumber':
        return OxTdlibAuthStateKind.waitingForPhoneNumber;
      case 'waitingForCode':
        return OxTdlibAuthStateKind.waitingForCode;
      case 'waitingForPassword':
        return OxTdlibAuthStateKind.waitingForPassword;
      case 'waitingForQrConfirmation':
        return OxTdlibAuthStateKind.waitingForQrConfirmation;
      case 'ready':
        return OxTdlibAuthStateKind.ready;
      case 'loggingOut':
        return OxTdlibAuthStateKind.loggingOut;
      case 'closed':
        return OxTdlibAuthStateKind.closed;
      case 'failed':
        return OxTdlibAuthStateKind.failed;
      case 'uninitialized':
      default:
        return OxTdlibAuthStateKind.uninitialized;
    }
  }

  OxTdlibAuthState currentAuthState() {
    final kind = _native.readCString(_native.currentAuthKind());
    final qr = _native.readCString(_native.currentAuthQr());
    final hint = _native.readCString(_native.currentAuthHint());
    final err = _native.readCString(_native.currentAuthError());
    _state = OxTdlibAuthState(
      kind: _kindFromString(kind),
      qrLoginUrl: _emptyToNull(qr),
      passwordHint: _emptyToNull(hint),
      errorMessage: _emptyToNull(err),
    );
    return _state;
  }

  Future<void> submitPhoneNumber(String phone) async {
    final p = phone.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitPhone(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> submitCode(String code) async {
    final p = code.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitCode(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> submitTwoFactorPassword(String password) async {
    final p = password.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.submitPassword(p));
    } finally {
      malloc.free(p);
    }
  }

  Future<void> requestQrLogin() async {
    _native.throwIfFailed(_native.requestQr());
  }

  Future<void> logOut() async {
    _native.throwIfFailed(_native.logout());
    _configured = false;
    _state = OxTdlibAuthState(kind: OxTdlibAuthStateKind.uninitialized);
  }

  Future<String> startPlaybackSession(OxTdlibPlaybackSource source) async {
    // Windows always uses HTTP bridge + libmpv (no Exo / tdlib-file://).
    final ch = source.channelUsername.toNativeUtf8();
    try {
      final urlPtr = _native.startPlayback(ch, source.messageId);
      if (urlPtr == nullptr) {
        final msg = _native.readCString(_native.lastError());
        throw OxTelegramNativeException(msg.isEmpty ? 'startPlayback failed' : msg);
      }
      return _native.readCString(urlPtr);
    } finally {
      malloc.free(ch);
    }
  }

  Future<void> stopPlaybackSession(String sessionUri) async {
    final p = sessionUri.toNativeUtf8();
    try {
      _native.throwIfFailed(_native.stopPlayback(p));
      // Keep Telegram client configured — stop only ends the progressive download.
    } finally {
      malloc.free(p);
    }
  }

  Future<String> fetchWebAppInitData(
    String botUsername,
    String? webAppShortName,
    String? hostedHttpsUrl,
  ) async {
    final bot = botUsername.toNativeUtf8();
    final short = (webAppShortName ?? '').toNativeUtf8();
    final hosted = (hostedHttpsUrl ?? '').toNativeUtf8();
    final platform = 'other'.toNativeUtf8();
    try {
      final ptr = _native.fetchWebApp(bot, short, hosted, platform);
      if (ptr == nullptr) {
        final msg = _native.readCString(_native.lastError());
        throw OxTelegramNativeException(msg.isEmpty ? 'fetchWebAppInitData failed' : msg);
      }
      return _native.readCString(ptr);
    } finally {
      malloc.free(bot);
      malloc.free(short);
      malloc.free(hosted);
      malloc.free(platform);
    }
  }
}

/// True when Windows oxtelegram.dll host should be used instead of Android Pigeon.
bool oxTelegramUseWindowsHost() => !kIsWeb && Platform.isWindows;
