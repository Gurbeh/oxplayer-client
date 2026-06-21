import 'package:sentry_flutter/sentry_flutter.dart';

/// Drops known-benign client errors so Sentry reflects actionable issues only.
abstract final class OxplayerSentryFilters {
  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    final message = _eventText(event);
    if (message != null && _shouldDrop(message)) return null;

    final tags = event.tags ?? {};
    if (tags['transient'] == 'true') return null;
    if (tags['perf'] == 'slow_screen') return null;

    return event;
  }

  static bool shouldReportPersistedLog(String message) {
    return !_shouldDrop(message);
  }

  static bool _shouldDrop(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('invalid statuscode: 404') &&
        (lower.contains('/images/logo') || lower.contains('/images/primary'))) {
      return true;
    }
    if (lower.contains('timeoutexception') && lower.contains('cachednetworkimageprovider')) {
      return true;
    }
    if (lower.contains('failed host lookup') || lower.contains('no address associated with hostname')) {
      return true;
    }
    if (lower.contains('item not in your library')) {
      return true;
    }
    if (lower.contains('null check operator used on a null value')) {
      return true;
    }
    if (lower.contains('api.github.com')) {
      return true;
    }

    return false;
  }

  static String? _eventText(SentryEvent event) {
    final throwable = event.throwable;
    if (throwable != null) return throwable.toString();
    return event.message?.formatted;
  }
}
