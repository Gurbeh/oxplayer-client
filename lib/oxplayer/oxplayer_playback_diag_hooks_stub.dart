/// Non-web: no DOM video hooks.
abstract final class OxplayerPlaybackDiagHooks {
  static void install() {}

  static void uninstall() {}

  static Map<String, Object?> snapshot() => const {};

  static bool get isInstalled => false;
}
