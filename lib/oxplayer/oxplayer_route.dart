import 'package:fladder/oxplayer/oxplayer_route_env.dart';

/// Active CDN edge for API + stream traffic.
enum OxplayerEdge {
  global,
  arvan;

  static OxplayerEdge? tryParse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'global':
      case 'cloudflare':
      case 'cf':
        return OxplayerEdge.global;
      case 'arvan':
        return OxplayerEdge.arvan;
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
      case OxplayerEdge.arvan:
        return OxplayerRouteEnv.arvanApiBaseUrl ?? OxplayerRouteEnv.globalApiBaseUrl;
    }
  }

  /// TCP target for Chopper / http — may pin Arvan edge IP while keeping logical host in [connectHostHeader].
  static String? get connectBaseUrl {
    final logical = apiBaseUrl;
    if (logical == null) return null;
    if (_active != OxplayerEdge.arvan) return logical;

    final pin = OxplayerRouteEnv.arvanEdgeAddr;
    if (pin == null || pin.isEmpty) return logical;

    final uri = Uri.parse(logical);
    return uri.replace(host: pin).toString();
  }

  /// Host header when [connectBaseUrl] uses an edge IP pin.
  static String? get connectHostHeader {
    if (_active != OxplayerEdge.arvan) return null;
    final pin = OxplayerRouteEnv.arvanEdgeAddr;
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
      case OxplayerEdge.arvan:
        return OxplayerRouteEnv.arvanStreamBaseUrl;
    }
  }

  /// Rewrites stream playback URLs for Arvan edge pin or vanity stream host.
  static String rewriteStreamUri(String url) {
    if (_active != OxplayerEdge.arvan) return url;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;

    var next = uri;

    final vanity = streamBaseUrl;
    if (vanity != null) {
      final vanityUri = Uri.tryParse(vanity);
      if (vanityUri != null &&
          vanityUri.hasAuthority &&
          _isGlobalStreamNodeHost(uri.host) &&
          uri.host != vanityUri.host) {
        next = next.replace(
          scheme: vanityUri.scheme,
          host: vanityUri.host,
          port: vanityUri.hasPort ? vanityUri.port : null,
        );
      }
    }

    final pin = OxplayerRouteEnv.arvanEdgeAddr;
    if (pin != null && pin.isNotEmpty && next.host != pin) {
      final logicalHost = next.host;
      next = next.replace(host: pin);
      // Caller / player must send Host: logicalHost when pinning; mpv uses URL host only.
      // Vanity stream.oxplayer.app on Arvan usually resolves correctly without pin.
      if (_isStreamHost(logicalHost)) {
        return next.toString();
      }
    }

    return next.toString();
  }

  static bool _isGlobalStreamNodeHost(String host) {
    final h = host.toLowerCase();
    return h.startsWith('stream-') && h.endsWith('.oxplayer.app');
  }

  static bool _isStreamHost(String host) {
    final h = host.toLowerCase();
    return h == 'stream.oxplayer.app' || _isGlobalStreamNodeHost(h);
  }
}
