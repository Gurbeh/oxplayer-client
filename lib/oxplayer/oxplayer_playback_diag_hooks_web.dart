import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('window.__oxPlaybackDiagInstall')
external void _oxPlaybackDiagInstall();

@JS('window.__oxPlaybackDiagUninstall')
external void _oxPlaybackDiagUninstall();

@JS('window.__oxPlaybackDiagSnapshotJson')
external String? _oxPlaybackDiagSnapshotJson();

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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {}
    return {'raw': raw};
  }

  static bool get isInstalled => _installed;
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
