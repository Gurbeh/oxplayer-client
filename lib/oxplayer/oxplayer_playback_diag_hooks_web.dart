import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

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

/// Web-only DOM hooks for stream / video diagnostics.
abstract final class OxplayerPlaybackDiagHooks {
  static bool _installed = false;

  static void install() {
    if (_installed) return;
    _installed = true;

    final script = web.HTMLScriptElement()
      ..type = 'text/javascript'
      ..text = _hookScript;
    web.document.head?.append(script);
    _oxPlaybackDiagInstall();
  }

  static void uninstall() {
    if (!_installed) return;
    _oxPlaybackDiagUninstall();
    _installed = false;
  }

  static Map<String, Object?> snapshot() {
    if (!_installed) return const {};
    final raw = _oxPlaybackDiagSnapshotJson();
    if (raw == null || raw.isEmpty) return const {};
    return _decodeMap(raw);
  }

  static bool get isInstalled => _installed;

  static Future<Map<String, Object?>> probeCdnRange(String url) async {
    install();
    try {
      final raw = await _oxPlaybackDiagFetchRange(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.runtimeType.toString()};
    }
  }

  static Future<Map<String, Object?>> probeVideoLoad(String url) async {
    install();
    try {
      final raw = await _oxPlaybackDiagProbeVideo(url.toJS).toDart;
      if (raw == null) return {'url': url, 'ok': false, 'error': 'empty_response'};
      return _decodeMap(raw.toDart);
    } catch (e) {
      return {'url': url, 'ok': false, 'error': e.runtimeType.toString()};
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

const _hookScript = r'''
(function () {
  if (window.__oxPlaybackDiag) return;

  const logs = [];
  const t0 = Date.now();
  const redact = (u) => {
    if (!u || typeof u !== 'string') return u;
    try {
      const x = new URL(u, location.href);
      if (x.searchParams.has('token')) x.searchParams.set('token', '***');
      if (x.searchParams.has('api_key')) x.searchParams.set('api_key', '***');
      return x.toString();
    } catch {
      return String(u).replace(/token=[^&]+/gi, 'token=***');
    }
  };
  const push = (type, data = {}) => {
    logs.push({ t: Date.now() - t0, type, ...data });
  };

  const hookVideo = (v) => {
    if (!v || v.__oxDiagHooked) return;
    v.__oxDiagHooked = true;
    const desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (!desc || !desc.set) return;
    Object.defineProperty(v, 'src', {
      configurable: true,
      get() { return desc.get.call(v); },
      set(val) {
        push('video_src', { url: redact(val) });
        return desc.set.call(v, val);
      },
    });
    if (v.src) push('video_src_existing', { url: redact(v.src) });
  };

  const state = { fetchPatched: false, observer: null, _fetch: null };

  window.__oxPlaybackDiagInstall = function () {
    if (!state.fetchPatched) {
      state._fetch = window.fetch.bind(window);
      window.fetch = async function (...args) {
        const url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
        if (url && /oxplayer|stream\/nodes|cdn\.ir|stream\.oxplayer/i.test(url)) {
          push('fetch', { url: redact(url) });
        }
        try {
          const res = await state._fetch(...args);
          if (url && /oxplayer|stream\/nodes|cdn\.ir|stream\.oxplayer/i.test(url)) {
            push('fetch_res', {
              url: redact(url),
              status: res.status,
              acao: res.headers.get('access-control-allow-origin'),
            });
          }
          return res;
        } catch (e) {
          if (url && /oxplayer|stream\/nodes|cdn\.ir|stream\.oxplayer/i.test(url)) {
            push('fetch_err', { url: redact(url), error: String(e) });
          }
          throw e;
        }
      };
      state.fetchPatched = true;
    }
    document.querySelectorAll('video').forEach(hookVideo);
    if (!state.observer) {
      state.observer = new MutationObserver(() => {
        document.querySelectorAll('video').forEach(hookVideo);
      });
      state.observer.observe(document.documentElement, { childList: true, subtree: true });
    }
  };

  window.__oxPlaybackDiagUninstall = function () {
    if (state.observer) {
      state.observer.disconnect();
      state.observer = null;
    }
    if (state.fetchPatched && state._fetch) {
      window.fetch = state._fetch;
      state.fetchPatched = false;
    }
  };

  window.__oxPlaybackDiagFetchRange = async function (url) {
    const t0 = Date.now();
    push('cdn_range_start', { url: redact(url) });
    try {
      const res = await fetch(url, { headers: { Range: 'bytes=0-1023' }, credentials: 'omit' });
      const out = {
        url: redact(url),
        ok: res.ok || res.status === 206,
        status: res.status,
        acao: res.headers.get('access-control-allow-origin'),
        elapsedMs: Date.now() - t0,
      };
      push('cdn_range_res', out);
      return JSON.stringify(out);
    } catch (e) {
      const out = {
        url: redact(url),
        ok: false,
        error: String(e),
        elapsedMs: Date.now() - t0,
      };
      push('cdn_range_err', out);
      return JSON.stringify(out);
    }
  };

  window.__oxPlaybackDiagProbeVideo = function (url) {
    return new Promise((resolve) => {
      const t0 = Date.now();
      push('probe_video_start', { url: redact(url) });
      const v = document.createElement('video');
      v.muted = true;
      v.playsInline = true;
      v.preload = 'auto';
      const finish = (out) => {
        try { v.removeAttribute('src'); v.load(); } catch (_) {}
        push('probe_video_done', out);
        resolve(JSON.stringify(out));
      };
      const timer = setTimeout(() => finish({
        url: redact(url),
        ok: false,
        error: 'timeout',
        readyState: v.readyState,
        networkState: v.networkState,
        elapsedMs: Date.now() - t0,
      }), 15000);
      v.addEventListener('loadedmetadata', () => {
        clearTimeout(timer);
        finish({
          url: redact(v.currentSrc || url),
          ok: true,
          readyState: v.readyState,
          networkState: v.networkState,
          duration: v.duration,
          elapsedMs: Date.now() - t0,
        });
      });
      v.addEventListener('error', () => {
        clearTimeout(timer);
        const err = v.error;
        finish({
          url: redact(v.currentSrc || url),
          ok: false,
          error: 'media_error',
          code: err ? err.code : null,
          message: err ? err.message : null,
          readyState: v.readyState,
          networkState: v.networkState,
          elapsedMs: Date.now() - t0,
        });
      });
      v.src = url;
    });
  };

  window.__oxPlaybackDiagSnapshotJson = function () {
    const videos = [...document.querySelectorAll('video')].map((v, i) => ({
      i,
      src: redact(v.currentSrc || v.src || ''),
      paused: v.paused,
      readyState: v.readyState,
      networkState: v.networkState,
      error: v.error ? { code: v.error.code, message: v.error.message } : null,
      duration: v.duration,
      currentTime: v.currentTime,
    }));
    return JSON.stringify({
      page: {
        href: location.href,
        host: location.host,
        ua: navigator.userAgent,
        online: navigator.onLine,
      },
      videos,
      logs,
      checks: {
        sawStreamNodes: logs.some((l) => l.type === 'fetch' && /stream\/nodes/.test(l.url || '')),
        sawCdnIrVideo: videos.some((v) => /\.ir\.cdn\.ir/i.test(v.src)),
        sawStreamOxplayerIr: videos.some((v) => /stream\.oxplayer\.ir/i.test(v.src)),
        sawStreamTs: videos.some((v) => /stream\.ts/i.test(v.src)),
        sawMkv: videos.some((v) => /\.mkv/i.test(v.src)),
      },
    });
  };

  window.__oxPlaybackDiag = { logs, push, redact };
})();
''';
