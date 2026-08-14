import 'package:shared_preferences/shared_preferences.dart';

/// How this device signed into OX — Telegram user session (phone/QR) vs main-bot approval.
enum OxplayerOxLoginKind {
  session,
  bot;

  static OxplayerOxLoginKind? tryParse(String? raw) {
    return switch (raw) {
      'session' => OxplayerOxLoginKind.session,
      'bot' => OxplayerOxLoginKind.bot,
      _ => null,
    };
  }
}

abstract final class OxplayerOxLoginKindStore {
  static const _keyPrefix = 'ox_login_kind_';

  static Future<void> save({
    required String accountId,
    required OxplayerOxLoginKind kind,
  }) async {
    final id = accountId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$id', kind.name);
  }

  static Future<OxplayerOxLoginKind?> read(String? accountId) async {
    final id = accountId?.trim() ?? '';
    if (id.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return OxplayerOxLoginKind.tryParse(prefs.getString('$_keyPrefix$id'));
  }

  /// Stored kind wins. Else: personal-bot token ≈ bot login; TDLib ready as a user ≈ session.
  /// OX logged in with native still waiting for phone (no user session) ≈ bot without /connectbot.
  static Future<OxplayerOxLoginKind?> resolve({
    required String? accountId,
    required bool tdlibUserSessionReady,
    required bool hasBotToken,
    required bool nativeWaitingForUserAuth,
  }) async {
    final stored = await read(accountId);
    if (stored != null) return stored;
    if (hasBotToken) return OxplayerOxLoginKind.bot;
    if (tdlibUserSessionReady) return OxplayerOxLoginKind.session;
    if (nativeWaitingForUserAuth) return OxplayerOxLoginKind.bot;
    return null;
  }
}
