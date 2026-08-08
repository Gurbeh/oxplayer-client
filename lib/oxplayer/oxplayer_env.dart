import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

abstract final class OxplayerEnv {
  /// True when this build targets OXPlayer (API base URL configured).
  static bool get isEnabled => apiBaseUrl != null;

  static const String _cApiBaseUrl = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cBotUsername = String.fromEnvironment('OXPLAYER_BOT_USERNAME', defaultValue: '');
  static const String _cSentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String _cSentryEnvironment = String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: '');
  // Telegram *user*-session (MTProto/TDLib) app credentials for client-side direct play — from
  // my.telegram.org, distinct from OXPLAYER_BOT_USERNAME (the bot-based OX login above).
  static const String _cTelegramApiId = String.fromEnvironment('TELEGRAM_API_ID', defaultValue: '');
  static const String _cTelegramApiHash = String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
  // Mini App identity used to sign in — a Web App must be registered on OXPLAYER_BOT_USERNAME via
  // @BotFather (short name and/or a hosted HTTPS Mini App URL) for GetWebAppLinkUrl/GetWebAppUrl
  // to succeed. See ox_tdlib_bridge's TdlibWebAppAuth.kt.
  static const String _cTelegramWebAppShortName =
      String.fromEnvironment('TELEGRAM_WEBAPP_SHORT_NAME', defaultValue: '');
  static const String _cTelegramHostedWebAppHttpsUrl =
      String.fromEnvironment('TELEGRAM_HOSTED_WEBAPP_HTTPS_URL', defaultValue: '');

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

  /// my.telegram.org app id for the user-session (MTProto/TDLib) direct-play client.
  static int? get telegramApiId {
    final t = _pick(['TELEGRAM_API_ID'], _cTelegramApiId);
    return t.isEmpty ? null : int.tryParse(t);
  }

  /// my.telegram.org app hash for the user-session (MTProto/TDLib) direct-play client.
  static String? get telegramApiHash {
    final t = _pick(['TELEGRAM_API_HASH'], _cTelegramApiHash);
    return t.isEmpty ? null : t;
  }

  /// True once both TDLib user-session credentials are configured for this build.
  static bool get telegramDirectPlayConfigured => telegramApiId != null && telegramApiHash != null;

  /// Mini App short name registered on the bot via @BotFather, for GetWebAppLinkUrl.
  static String? get telegramWebAppShortName {
    final t = _pick(['TELEGRAM_WEBAPP_SHORT_NAME'], _cTelegramWebAppShortName);
    return t.isEmpty ? null : t;
  }

  /// Fallback hosted HTTPS Mini App URL, for GetWebAppUrl when no short name is set/works.
  static String? get telegramHostedWebAppHttpsUrl {
    final t = _pick(['TELEGRAM_HOSTED_WEBAPP_HTTPS_URL'], _cTelegramHostedWebAppHttpsUrl);
    return t.isEmpty ? null : t;
  }
}
