import 'dart:convert';
import 'dart:js_interop';

/// Web-only DOM hooks for stream / video diagnostics.
/// Bootstrap lives in [web/ox-playback-diag.js] (loaded from index.html).
abstract final class OxplayerPlaybackDiagHooks {
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    try {
      _oxPlaybackDiagInstall();
      _installed = true;
    } catch (e) {
      _installed = false;
    }
  }

  static void uninstall() {
    if (!_installed) return;
    try {
      _oxPlaybackDiagUninstall();
    } catch (_) {}
    _installed = false;
  }

  static Map<String, Object?> snapshot() {
    if (!_installed) return const {};
    try {
      final raw = _oxPlaybackDiagSnapshotJson();
      if (raw == null || raw.isEmpty) return const {};
      return _decodeMap(raw);
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  static bool get isInstalled => _installed;

  static Future<Map<String, Object?>> probeCdnRange(String url) async {
    try {
      install();
      if (!_installed) {
        return {'url': url, 'ok': false, 'error': 'hooks_unavailable'};
      }
      final raw = await _oxPlaybackDiagFetchRange(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, Object?>> probeVideoLoad(String url) async {
    try {
      install();
      if (!_installed) {
        return {'url': url, 'ok': false, 'error': 'hooks_unavailable'};
      }
      final raw = await _oxPlaybackDiagProbeVideo(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.toString()};
    }
  }

  static Map<String, Object?> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return {'raw': raw};
  }
}

@JS('window.__oxPlaybackDiagInstall')
external void _oxPlaybackDiagInstall();

@JS('window.__oxPlaybackDiagUninstall')
external void _oxPlaybackDiagUninstall();

@JS('window.__oxPlaybackDiagSnapshotJson')
external String? _oxPlaybackDiagSnapshotJson();

@JS('window.__oxPlaybackDiagFetchRange')
external JSPromise<JSString?> _oxPlaybackDiagFetchRange(JSString url);

@JS('window.__oxPlaybackDiagProbeVideo')
external JSPromise<JSString?> _oxPlaybackDiagProbeVideo(JSString url);
