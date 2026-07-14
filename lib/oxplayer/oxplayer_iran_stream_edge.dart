import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';

/// Iran stream vanity host 302 → edge shard; Authorization dropped on redirect.
/// Resolve edge host and keep JWT in ?token=.
abstract final class OxplayerIranStreamEdge {
  /// Direct Iran stream origin when vanity probe fails or web cannot follow redirect.
  static const iranStreamOriginHost = 'stream.oxplayer.ir';

  static final Map<String, String> _resolveCache = {};

  static bool isIranVanityStreamHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return host.toLowerCase().endsWith('.ir.cdn.ir');
  }

  static bool isIranVanityStreamUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return isIranVanityStreamHost(Uri.tryParse(url)?.host);
  }

  static bool _isVanityHost(String host) {
    final h = host.toLowerCase();
    return isIranVanityStreamHost(h) && !h.startsWith('edge');
  }

  static String _cacheKey(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

  /// Vanity → edge redirect; re-attaches stream JWT. Falls back to [iranStreamOriginHost].
  static Future<String> resolvePlaybackUrl(String url) async {
    if (!oxplayerIsOxStreamUrl(url) || !isIranVanityStreamUrl(url)) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    final host = uri.host.toLowerCase();
    final token = uri.queryParameters['token']?.trim();

    // Web cannot read vanity Location (CORS); bypass edge shards and node vanity hosts.
    if (kIsWeb && isIranVanityStreamHost(host)) {
      return rewriteWebPlaybackUrl(_fallbackIranOrigin(uri, token));
    }

    if (!_isVanityHost(host)) return url;

    final cached = _resolveCache[_cacheKey(uri)];
    if (cached != null && cached.isNotEmpty) return cached;

    final resolved = await _probeVanityRedirect(uri, token) ?? _fallbackIranOrigin(uri, token);
    _resolveCache[_cacheKey(uri)] = resolved;
    return resolved;
  }

  /// GET + Range (HEAD hangs on vanity); do not follow redirect to edge.
  static Future<String?> _probeVanityRedirect(Uri uri, String? token) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri)..headers['Range'] = 'bytes=0-0';
      final res = await client.send(req).timeout(const Duration(seconds: 5));
      try {
        final status = res.statusCode;
        OxplayerStreamLog.event('iran_stream_edge_probe', fields: {
          'fromHost': uri.host,
          'status': status,
        });
        if (status < 300 || status >= 400) return null;

        final loc = res.headers['location'] ?? res.headers['Location'];
        if (loc == null || loc.trim().isEmpty) return null;

        final edge = Uri.parse(loc.trim());
        if (!isIranVanityStreamHost(edge.host) || edge.host.toLowerCase() == uri.host.toLowerCase()) {
          return null;
        }

        final params = Map<String, String>.from(edge.queryParameters);
        if (token != null && token.isNotEmpty) {
          params['token'] = token;
        }
        final out = edge.replace(queryParameters: params).toString();
        OxplayerStreamLog.event('iran_stream_edge_resolve', fields: {
          'fromHost': uri.host,
          'toHost': edge.host,
          'hasToken': token != null && token.isNotEmpty,
          'finalUrl': OxplayerStreamLog.describeUrl(out),
        });
        return out;
      } finally {
        await res.stream.drain();
      }
    } catch (e) {
      OxplayerStreamLog.event('iran_stream_edge_resolve', fields: {
        'fromHost': uri.host,
        'error': e.runtimeType.toString(),
      });
      return null;
    } finally {
      client.close();
    }
  }

  static String _fallbackIranOrigin(Uri vanity, String? token) {
    final params = Map<String, String>.from(vanity.queryParameters);
    if (token != null && token.isNotEmpty) {
      params['token'] = token;
    }
    final out = vanity.replace(
      scheme: 'https',
      host: iranStreamOriginHost,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    OxplayerStreamLog.event('iran_stream_origin_fallback', fields: {
      'fromHost': vanity.host,
      'toHost': iranStreamOriginHost,
      'finalUrl': OxplayerStreamLog.describeUrl(out),
    });
    return out;
  }

  /// Web progressive playback: MKV is not a native <video> codec — use remux TS path.
  static String rewriteWebPlaybackUrl(String url) {
    if (!kIsWeb || !oxplayerIsOxStreamUrl(url)) return url;
    if (url.contains('/stream.ts') || url.contains('stream.ts?')) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    final match = RegExp(r'^/v/([A-Za-z0-9_-]+)\.[^/]+$').firstMatch(uri.path);
    if (match == null) return url;

    final out = uri.replace(path: '/v/${match.group(1)}.stream.ts').toString();
    if (out != url) {
      OxplayerStreamLog.event('web_stream_remux_path', fields: {
        'before': OxplayerStreamLog.describeUrl(url),
        'after': OxplayerStreamLog.describeUrl(out),
      });
    }
    return out;
  }

  static void clearCache() => _resolveCache.clear();
}
