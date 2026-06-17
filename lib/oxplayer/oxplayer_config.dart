import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

/// Master switch for OXPlayer-specific behavior.
///
/// Enabled by default; disable with `--dart-define=OXPLAYER=false` or
/// `OXPLAYER=false` in `assets/env/default.env`.
abstract final class OxplayerConfig {
  static const bool _cEnabled = bool.fromEnvironment('OXPLAYER', defaultValue: true);

  static bool get isEnabled {
    if (!_cEnabled) return false;
    final env = OxplayerDotenv.get('OXPLAYER').trim().toLowerCase();
    if (env == 'false') return false;
    return true;
  }
}
