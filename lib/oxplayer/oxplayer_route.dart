import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';

/// Active CDN edge for API + stream traffic.
enum OxplayerEdge {
  global,
  iran;

  static OxplayerEdge? tryParse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'global':
      case 'cloudflare':
      case 'cf':
        return OxplayerEdge.global;
      case 'iran':
      case 'arvan':
        return OxplayerEdge.iran;
      default:
        return null;
    }
  }
}

/// Runtime route selection — updated at startup and on HTTP 451.
abstract final class OxplayerRoute {
  static OxplayerEdge _active = OxplayerEdge.global;

  static OxplayerEdge get active => _active;

  static void setActive(OxplayerEdge edge) {
    _active = edge;
  }

  /// Logical API base URL for the active edge (hostname from env).
  static String? get apiBaseUrl {
    switch (_active) {
      case OxplayerEdge.global:
        return OxplayerRouteEnv.globalApiBaseUrl;
      case OxplayerEdge.iran:
        return OxplayerRouteEnv.iranApiBaseUrl ?? OxplayerRouteEnv.globalApiBaseUrl;
    }
  }

  /// TCP target for Chopper / http — may pin edge IP while keeping logical host in [connectHostHeader].
  static String? get connectBaseUrl {
    final logical = apiBaseUrl;
    if (logical == null) return null;
    if (_active != OxplayerEdge.iran) return logical;

    final pin = OxplayerRouteEnv.iranEdgeAddr;
    if (pin == null || pin.isEmpty) return logical;

    final uri = Uri.parse(logical);
    return uri.replace(host: pin).toString();
  }

  /// Host header when [connectBaseUrl] uses an edge IP pin.
  static String? get connectHostHeader {
    if (_active != OxplayerEdge.iran) return null;
    final pin = OxplayerRouteEnv.iranEdgeAddr;
    if (pin == null || pin.isEmpty) return null;
    return Uri.tryParse(apiBaseUrl ?? '')?.host;
  }

  static Map<String, String> get connectHeaders {
    final host = connectHostHeader;
    if (host == null || host.isEmpty) return const {};
    return {'Host': host};
  }

  static String? get streamBaseUrl {
    switch (_active) {
      case OxplayerEdge.global:
        return null;
      case OxplayerEdge.iran:
        return OxplayerRouteEnv.iranStreamBaseUrl;
    }
  }

  /// Rewrites stream playback URLs for Iran edge pin or vanity stream host.
  static String rewriteStreamUri(String url) {
    final before = url;
    url = OxplayerRouteEnv.rewriteLegacyIranUrl(url);
    if (_active != OxplayerEdge.iran) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    var next = uri;
    String? rewriteKind;

    final vanity = streamBaseUrl;
    if (vanity != null) {
      final vanityUri = Uri.tryParse(vanity);
      if (vanityUri != null &&
          vanityUri.hasAuthority &&
          _isStreamHost(uri.host) &&
          uri.host != vanityUri.host) {
        next = next.replace(
          scheme: vanityUri.scheme,
          host: vanityUri.host,
        );
        rewriteKind = 'iran_stream_vanity';
      }
    }

    final pin = OxplayerRouteEnv.iranEdgeAddr;
    if (pin != null && pin.isNotEmpty && next.host != pin) {
      final logicalHost = next.host;
      next = next.replace(host: pin);
      if (_isStreamHost(logicalHost)) {
        OxplayerStreamLog.event('rewrite_stream', fields: {
          'kind': rewriteKind ?? 'iran_edge_pin',
          'before': OxplayerStreamLog.describeUrl(before),
          'after': OxplayerStreamLog.describeUrl(next.toString()),
        });
        return next.toString();
      }
    }

    if (before != next.toString()) {
      OxplayerStreamLog.event('rewrite_stream', fields: {
        'kind': rewriteKind ?? 'iran_vanity',
        'before': OxplayerStreamLog.describeUrl(before),
        'after': OxplayerStreamLog.describeUrl(next.toString()),
      });
    }
    return next.toString();
  }

  static bool _isGlobalStreamNodeHost(String host) {
    final h = host.toLowerCase();
    return h.startsWith('stream-') && h.endsWith('.oxplayer.app');
  }

  static bool _isStreamHost(String host) {
    final h = host.toLowerCase();
    return h == 'stream.oxplayer.app' ||
        h == 'stream.oxplayer.ir' ||
        _isGlobalStreamNodeHost(h);
  }
}
