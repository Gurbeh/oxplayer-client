import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_cdn_ir_edge.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';

/// Bearer auth for ox-stream when edge caches by path only (not CDN.ir vanity redirect).
abstract final class OxplayerStreamHttpAuth {
  static final Map<String, String> _bearerByKey = {};

  static const String _cHeaderAuth = String.fromEnvironment(
    'OXPLAYER_STREAM_HEADER_AUTH',
    defaultValue: '',
  );

  /// True when stream JWT should move from query string to Authorization header.
  static bool get headerAuthEnabled {
    if (!OxplayerEnv.isEnabled) return false;
    return _explicitHeaderAuth;
  }

  static bool get _explicitHeaderAuth {
    final d = _cHeaderAuth.trim().toLowerCase();
    return d == '1' || d == 'true' || d == 'yes';
  }

  /// CDN.ir uses ?token= — vanity 302 to edge drops Authorization headers.
  static bool needsHeaderAuthForUrl(String url) {
    if (!OxplayerEnv.isEnabled || !oxplayerIsOxStreamUrl(url)) return false;
    if (OxplayerCdnIrEdge.isCdnIrUrl(url)) return false;
    return _explicitHeaderAuth;
  }

  static String _key(Uri uri) => '${uri.scheme}://${uri.host}${uri.path}';

  static String? bearerFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return _bearerByKey[_key(uri)];
  }

  /// Removes ?token= from playback URL and stores bearer for the player HTTP stack.
  static String stripAndRegister(String url) {
    if (!needsHeaderAuthForUrl(url)) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.isEmpty) return url;
    final params = Map<String, String>.from(uri.queryParameters)..remove('token');
    final clean = uri.replace(queryParameters: params).toString();
    _bearerByKey[_key(uri.replace(queryParameters: params))] = token;
    return clean;
  }

  static void clear() => _bearerByKey.clear();
}
