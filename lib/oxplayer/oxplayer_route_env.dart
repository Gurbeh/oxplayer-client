import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// Env keys for dual-edge routing (global Cloudflare vs Iran CDN.ir / .ir).
abstract final class OxplayerRouteEnv {
  static const String _cGlobalApi = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cIranApi = String.fromEnvironment('OXPLAYER_API_BASE_IRAN', defaultValue: '');
  static const String _cIranStream = String.fromEnvironment('OXPLAYER_STREAM_BASE_IRAN', defaultValue: '');
  static const String _cIranEdgeAddr = String.fromEnvironment('OXPLAYER_IRAN_EDGE_ADDR', defaultValue: '');
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
    final t = _rewriteLegacyIranHost(raw.trim());
    if (t.isEmpty) return null;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  /// CI builds before oxplayer.ir migration may still embed kabazhe.ir in dart-defines.
  static String rewriteLegacyIranUrl(String raw) => _rewriteLegacyIranHost(raw);

  static String _rewriteLegacyIranHost(String raw) {
    return raw
        .replaceAll('api.kabazhe.ir', 'api.oxplayer.ir')
        .replaceAll('stream.kabazhe.ir', 'stream.oxplayer.ir')
        .replaceAll('www.kabazhe.ir', 'www.oxplayer.ir')
        .replaceAll('kabazhe.ir', 'oxplayer.ir');
  }

  static String? get globalApiBaseUrl => _normalizeBase(_pick(['OXPLAYER_API_BASE_URL', 'OXPLAYER_API_BASE'], _cGlobalApi));

  static String? get iranApiBaseUrl =>
      _normalizeBase(_pick(['OXPLAYER_API_BASE_IRAN', 'OXPLAYER_API_BASE_ARVAN'], _cIranApi)) ??
      'https://api.oxplayer.ir';

  static String? get iranStreamBaseUrl =>
      _normalizeBase(_pick(['OXPLAYER_STREAM_BASE_IRAN', 'OXPLAYER_STREAM_BASE_ARVAN'], _cIranStream)) ??
      'https://oxstream.256251.ir.cdn.ir';

  static String? get iranEdgeAddr {
    final t = _pick(['OXPLAYER_IRAN_EDGE_ADDR', 'OXPLAYER_ARVAN_EDGE_ADDR'], _cIranEdgeAddr);
    return t.isEmpty ? null : t;
  }

  /// `global` or `iran` — forces edge regardless of probe / 451.
  static String? get forceEdge {
    final t = _pick(['OXPLAYER_FORCE_EDGE'], _cForceEdge).toLowerCase();
    return t.isEmpty ? null : t;
  }

  static bool get hasIranRoute => iranApiBaseUrl != null;
}
