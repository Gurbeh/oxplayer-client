import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';

/// CDN.ir vanity (`oxstream.*.ir.cdn.ir`) 302 → `edgeNN.*.ir.cdn.ir` and drops
/// Authorization on redirect. Resolve edge host and keep JWT in ?token=.
abstract final class OxplayerCdnIrEdge {
  /// Arvan stream origin — bypass when CDN.ir vanity probe fails.
  static const arvanStreamHost = 'stream.oxplayer.ir';

  static final Map<String, String> _resolveCache = {};

  static bool isCdnIrHost(String? host) {
    if (host == null || host.isEmpty) return false;
    return host.toLowerCase().endsWith('.ir.cdn.ir');
  }

  static bool isCdnIrUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    return isCdnIrHost(Uri.tryParse(url)?.host);
  }

  static bool _isVanityHost(String host) {
    final h = host.toLowerCase();
    return isCdnIrHost(h) && !h.startsWith('edge');
  }

  static String _cacheKey(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

  /// Vanity → edge redirect; re-attaches stream JWT. Falls back to [arvanStreamHost].
  static Future<String> resolvePlaybackUrl(String url) async {
    if (!oxplayerIsOxStreamUrl(url) || !isCdnIrUrl(url)) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    final host = uri.host.toLowerCase();
    if (!_isVanityHost(host)) return url;

    // Browser cannot read CDN.ir vanity Location (CORS); use Arvan stream (CORS-enabled).
    if (kIsWeb) {
      final token = uri.queryParameters['token']?.trim();
      return _fallbackArvanOrigin(uri, token);
    }

    final cached = _resolveCache[_cacheKey(uri)];
    if (cached != null && cached.isNotEmpty) return cached;

    final token = uri.queryParameters['token']?.trim();
    final resolved = await _probeVanityRedirect(uri, token) ?? _fallbackArvanOrigin(uri, token);
    _resolveCache[_cacheKey(uri)] = resolved;
    return resolved;
  }

  /// GET + Range (HEAD hangs on CDN.ir vanity); do not follow redirect to edge.
  static Future<String?> _probeVanityRedirect(Uri uri, String? token) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', uri)..headers['Range'] = 'bytes=0-0';
      final res = await client.send(req).timeout(const Duration(seconds: 5));
      try {
        final status = res.statusCode;
        OxplayerStreamLog.event('cdn_ir_edge_probe', fields: {
          'fromHost': uri.host,
          'status': status,
        });
        if (status < 300 || status >= 400) return null;

        final loc = res.headers['location'] ?? res.headers['Location'];
        if (loc == null || loc.trim().isEmpty) return null;

        final edge = Uri.parse(loc.trim());
        if (!isCdnIrHost(edge.host) || edge.host.toLowerCase() == uri.host.toLowerCase()) {
          return null;
        }

        final params = Map<String, String>.from(edge.queryParameters);
        if (token != null && token.isNotEmpty) {
          params['token'] = token;
        }
        final out = edge.replace(queryParameters: params).toString();
        OxplayerStreamLog.event('cdn_ir_edge_resolve', fields: {
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
      OxplayerStreamLog.event('cdn_ir_edge_resolve', fields: {
        'fromHost': uri.host,
        'error': e.runtimeType.toString(),
      });
      return null;
    } finally {
      client.close();
    }
  }

  static String _fallbackArvanOrigin(Uri vanity, String? token) {
    final params = Map<String, String>.from(vanity.queryParameters);
    if (token != null && token.isNotEmpty) {
      params['token'] = token;
    }
    final out = vanity.replace(
      scheme: 'https',
      host: arvanStreamHost,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    OxplayerStreamLog.event('cdn_ir_arvan_fallback', fields: {
      'fromHost': vanity.host,
      'toHost': arvanStreamHost,
      'finalUrl': OxplayerStreamLog.describeUrl(out),
    });
    return out;
  }

  static void clearCache() => _resolveCache.clear();
}
