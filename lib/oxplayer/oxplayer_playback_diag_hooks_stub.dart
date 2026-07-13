/// Non-web: no DOM video hooks.
abstract final class OxplayerPlaybackDiagHooks {
  static void install() {}

  static void uninstall() {}

  static Map<String, Object?> snapshot() => const {};

  static bool get isInstalled => false;

  static Future<Map<String, Object?>> probeCdnRange(String url) async => {
        'skipped': true,
        'reason': 'not_web',
      };

  static Future<Map<String, Object?>> probeVideoLoad(String url) async => {
        'skipped': true,
        'reason': 'not_web',
      };
}
