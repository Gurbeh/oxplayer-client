import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

abstract final class OxplayerEnv {
  /// True when this build targets OXPlayer (API base URL configured).
  static bool get isEnabled => apiBaseUrl != null;

  static const String _cApiBaseUrl = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cBotUsername = String.fromEnvironment('OXPLAYER_BOT_USERNAME', defaultValue: '');
  static const String _cSentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String _cSentryEnvironment = String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: '');

  static String _pick(List<String> keys, String define) {
    final d = define.trim();
    if (d.isNotEmpty) return d;
    for (final k in keys) {
      final v = OxplayerDotenv.get(k).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String? get apiBaseUrl {
    final t = _pick(['OXPLAYER_API_BASE_URL', 'OXPLAYER_API_BASE'], _cApiBaseUrl);
    if (t.isEmpty) return null;
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  static String? get effectiveMediaServerUrl => apiBaseUrl;

  static String? get botUsername {
    final t = _pick(['OXPLAYER_BOT_USERNAME', 'BOT_USERNAME'], _cBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? null : t;
  }

  static String? get telegramBotOpenLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b';
  }

  static String? get telegramBotLoginLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b?start=login';
  }

  /// Deep link for self-service account delete in the main bot.
  static String? get telegramBotDeleteAccountLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b?start=delete_account';
  }

  /// Deep link for app login attempt: ?start=li_<32-char hex attemptId>.
  static String? get sentryDsn {
    final t = _pick(['SENTRY_DSN'], _cSentryDsn);
    return t.isEmpty ? null : t;
  }

  static String? get sentryEnvironment {
    final t = _pick(['SENTRY_ENVIRONMENT'], _cSentryEnvironment);
    return t.isEmpty ? null : t;
  }

  static String? telegramBotLoginAttemptLink(String attemptId) {
    final b = botUsername;
    final id = attemptId.trim();
    if (b == null || id.isEmpty) return null;
    return 'https://telegram.me/$b?start=li_$id';
  }
}
