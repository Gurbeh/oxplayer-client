import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Which Fladder settings entries are shown in OXPlayer builds.
abstract final class OxplayerSettingsVisibility {
  static bool get isOxMode => OxplayerConfig.isEnabled;

  static bool get showControlPanel => !isOxMode;

  static bool get showSwitchUser => !isOxMode;

  static bool get showProfilePasswordReset => !isOxMode;

  static bool get showProfileSubtitlePreferences => !isOxMode;

  static bool get showProfileJellyfinNotifications => !isOxMode;

  static bool get showProfileLocalUrl => !isOxMode;

  /// Full library order editor (reorder + latest excludes + hide played).
  static bool get showProfileLibraryOrder => !isOxMode;

  /// Grouped libraries checkboxes (persisted via UserConfiguration on the server).
  static bool get showProfileGroupedFolders => true;

  static bool get showProfileHomePreferencesSave =>
      showProfileLibraryOrder || (isOxMode && showProfileGroupedFolders);
}
