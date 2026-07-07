import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// Env keys for dual-edge routing (global Cloudflare vs Arvan Iran CDN).
abstract final class OxplayerRouteEnv {
  static const String _cGlobalApi = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cArvanApi = String.fromEnvironment('OXPLAYER_API_BASE_ARVAN', defaultValue: '');
  static const String _cArvanStream = String.fromEnvironment('OXPLAYER_STREAM_BASE_ARVAN', defaultValue: '');
  static const String _cArvanEdgeAddr = String.fromEnvironment('OXPLAYER_ARVAN_EDGE_ADDR', defaultValue: '');
  static const String _cForceEdge = String.fromEnvironment('OXPLAYER_FORCE_EDGE', defaultValue: '');

  static String _pick(List<String> keys, String define) {
    final d = define.trim();
    if (d.isNotEmpty) return d;
    for (final k in keys) {
      final v = OxplayerDotenv.get(k).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String? _normalizeBase(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  static String? get globalApiBaseUrl => _normalizeBase(_pick(['OXPLAYER_API_BASE_URL', 'OXPLAYER_API_BASE'], _cGlobalApi));

  static String? get arvanApiBaseUrl =>
      _normalizeBase(_pick(['OXPLAYER_API_BASE_ARVAN'], _cArvanApi)) ??
      'https://api.kabazhe.ir';

  static String? get arvanStreamBaseUrl =>
      _normalizeBase(_pick(['OXPLAYER_STREAM_BASE_ARVAN'], _cArvanStream)) ??
      'https://stream.kabazhe.ir';

  static String? get arvanEdgeAddr {
    final t = _pick(['OXPLAYER_ARVAN_EDGE_ADDR'], _cArvanEdgeAddr);
    return t.isEmpty ? null : t;
  }

  /// `global` or `arvan` — forces edge regardless of probe / 451.
  static String? get forceEdge {
    final t = _pick(['OXPLAYER_FORCE_EDGE'], _cForceEdge).toLowerCase();
    return t.isEmpty ? null : t;
  }

  static bool get hasArvanRoute => arvanApiBaseUrl != null;
}
