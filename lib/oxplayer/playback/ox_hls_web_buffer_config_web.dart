import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Aggressive HLS.js buffer defaults for web playback (2–4 MB server chunks).
abstract final class OxHlsWebBufferConfig {
  static const int maxBufferLengthSeconds = 90;
  static const int maxBufferSizeBytes = 150000000;

  static const String _hlsAsset = 'assets/packages/media_kit/assets/web/hls1.4.10.js';

  static bool _applied = false;
  static Completer<void>? _loadCompleter;

  static Future<void> apply() async {
    if (_applied) {
      return;
    }

    await _ensureHlsLoaded();
    _hlsMaxBufferLength = maxBufferLengthSeconds;
    _hlsMaxBufferSize = maxBufferSizeBytes;
    _applied = true;
  }

  static Future<void> _ensureHlsLoaded() async {
    if (_isHlsLoaded()) {
      return;
    }

    final inFlight = _loadCompleter;
    if (inFlight != null) {
      return inFlight.future;
    }

    final completer = Completer<void>();
    _loadCompleter = completer;

    final script = web.HTMLScriptElement()
      ..async = true
      ..charset = 'utf-8'
      ..type = 'text/javascript'
      ..src = _hlsAsset;

    script.onLoad.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    script.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Failed to load HLS.js'));
      }
    });

    final head = web.document.head ?? web.HTMLHeadElement();
    if (web.document.head == null) {
      web.document.append(head);
    }
    head.append(script);
    await completer.future;
  }

  static bool _isHlsLoaded() => _hls != null;
}

@JS('Hls')
external JSAny? get _hls;

@JS('Hls.DefaultConfig.maxBufferLength')
external set _hlsMaxBufferLength(num value);

@JS('Hls.DefaultConfig.maxBufferSize')
external set _hlsMaxBufferSize(num value);
