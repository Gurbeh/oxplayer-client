/// No-op on platforms without JS interop (mobile, desktop native).
abstract final class OxHlsWebBufferConfig {
  static Future<void> apply() async {}
}
