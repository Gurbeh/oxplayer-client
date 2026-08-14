import 'package:fladder/oxplayer/oxplayer_dotenv.dart';

abstract final class OxplayerEnv {
  /// True when this build targets OXPlayer (API base URL configured).
  static bool get isEnabled => apiBaseUrl != null;

  static const String _cApiBaseUrl = String.fromEnvironment('OXPLAYER_API_BASE_URL', defaultValue: '');
  static const String _cBotUsername = String.fromEnvironment('OXPLAYER_BOT_USERNAME', defaultValue: '');
  static const String _cSentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');
  static const String _cSentryEnvironment = String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: '');
  // Telegram *user*-session (MTProto/TDLib) app credentials — from my.telegram.org, distinct from
  // OXPLAYER_BOT_USERNAME (customer-facing main bot) and TELEGRAM_WEBAPP_BOT_USERNAME (Mini App).
  static const String _cTelegramApiId = String.fromEnvironment('TELEGRAM_API_ID', defaultValue: '');
  static const String _cTelegramApiHash = String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: '');
  // Mini App identity used to sign in — a Web App must be registered via @BotFather (short name
  // and/or a hosted HTTPS Mini App URL) on TELEGRAM_WEBAPP_BOT_USERNAME for GetWebAppLinkUrl/
  // GetWebAppUrl to succeed. See go/oxtelegram/webapp.go's FetchWebAppInitData.
  static const String _cTelegramWebAppShortName =
      String.fromEnvironment('TELEGRAM_WEBAPP_SHORT_NAME', defaultValue: '');
  static const String _cTelegramHostedWebAppHttpsUrl =
      String.fromEnvironment('TELEGRAM_HOSTED_WEBAPP_HTTPS_URL', defaultValue: '');
  // Deliberately a separate bot from OXPLAYER_BOT_USERNAME: registering a bot's Main Mini App also
  // makes Telegram show a persistent "OPEN" button on that bot's own chat screen for every user,
  // and OXPLAYER_BOT_USERNAME (main-bot) is customer-facing — that dead-looking button (this fetch
  // never actually opens the page a human would land on) is confusing there. Falls back to
  // OXPLAYER_BOT_USERNAME so builds that haven't provisioned a dedicated auth bot keep working.
  static const String _cTelegramWebAppBotUsername =
      String.fromEnvironment('TELEGRAM_WEBAPP_BOT_USERNAME', defaultValue: '');

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
    final t = _pick(['OXPLAYER_BOT_USERNAME', 'BOT_USERNAME', 'TELEGRAM_MAIN_BOT_USERNAME'], _cBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? null : t;
  }

  static String? get telegramBotOpenLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b';
  }

  /// Deep link for self-service account delete in the main bot.
  static String? get telegramBotDeleteAccountLink {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b?start=delete_account';
  }

  /// Deep link that opens the main bot with a pending login attempt pre-approved for Yes/No —
  /// see apps/main-bot/internal/bot/login_attempt.go's handleStartLoginAttemptDeepLink
  /// (?start=li_<32-hex-attemptId>).
  static String? telegramBotLoginAttemptLink(String attemptId) {
    final b = botUsername;
    return b == null ? null : 'https://telegram.me/$b?start=li_$attemptId';
  }

  static String? get sentryDsn {
    final t = _pick(['SENTRY_DSN'], _cSentryDsn);
    return t.isEmpty ? null : t;
  }

  static String? get sentryEnvironment {
    final t = _pick(['SENTRY_ENVIRONMENT'], _cSentryEnvironment);
    return t.isEmpty ? null : t;
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

  /// Bot the Mini App initData fetch resolves against (see fetchWebAppInitData) — falls back to
  /// botUsername (main-bot) when no dedicated auth bot is configured for this build.
  static String? get telegramWebAppBotUsername {
    final t = _pick(['TELEGRAM_WEBAPP_BOT_USERNAME'], _cTelegramWebAppBotUsername)
        .replaceFirst(RegExp(r'^@'), '');
    return t.isEmpty ? botUsername : t;
  }
}
