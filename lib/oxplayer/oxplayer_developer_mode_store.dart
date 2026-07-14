import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the About-screen developer mode easter egg is unlocked.
abstract final class OxplayerDeveloperModeStore {
  static const _key = 'ox_developer_mode_unlocked';

  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> unlock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
