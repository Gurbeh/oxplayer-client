import 'package:sentry_flutter/sentry_flutter.dart';

/// Drops known-benign client errors so Sentry reflects actionable issues only.
abstract final class OxplayerSentryFilters {
  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    final message = _eventText(event);
    if (message != null && _shouldDrop(message)) return null;
    if (_isBenignAnr(event)) return null;

    final tags = event.tags ?? {};
    if (tags['transient'] == 'true') return null;
    if (tags['perf'] == 'slow_screen' || tags['perf'] == 'slow_splash') return null;

    final stack = event.exceptions?.map((e) => e.stackTrace?.frames ?? []).expand((f) => f);
    if (stack != null) {
      for (final frame in stack) {
        final symbol = frame.symbol ?? '';
        if (symbol.contains('LiveText.isLiveTextInputAvailable') ||
            symbol.contains('LiveTextInputStatusNotifier')) {
          return null;
        }
      }
    }

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
    if (lower.contains('404 not found')) {
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

  /// Drops ANRs from Google Play license verification on sideloaded/emulator builds.
  static bool _isBenignAnr(SentryEvent event) {
    final parts = <String>[
      _eventText(event) ?? '',
      event.message?.formatted ?? '',
      for (final ex in event.exceptions ?? const []) ex.value ?? '',
      for (final ex in event.exceptions ?? const [])
        for (final frame in ex.stackTrace?.frames ?? const []) frame.symbol ?? '',
    ];
    final text = parts.join(' ').toLowerCase();
    if (!text.contains('applicationnotresponding') && !text.contains(' anr')) {
      return false;
    }

    if (text.contains('pairip') ||
        text.contains('licenseactivity') ||
        text.contains('licensecheck')) {
      return true;
    }

    final viewNames = event.contexts.app?.viewNames ?? const <String>[];
    if (viewNames.any((v) => v.toLowerCase().contains('license'))) {
      return true;
    }

    if (event.tags?['isSideLoaded'] == 'true') {
      final osBuild = (event.contexts.operatingSystem?.build ?? '').toLowerCase();
      if (osBuild.contains('test-keys') ||
          osBuild.contains('sdk_phone') ||
          osBuild.contains('-eng ')) {
        return true;
      }
    }

    return false;
  }

  static String? _eventText(SentryEvent event) {
    final throwable = event.throwable;
    if (throwable != null) return throwable.toString();
    return event.message?.formatted;
  }
}
