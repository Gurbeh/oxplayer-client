import 'package:sentry_flutter/sentry_flutter.dart';

/// Reports video playback failures and related server/stream HTTP to Sentry.
abstract final class OxplayerPlaybackTelemetry {
  static Future<void> reportFailure({
    required String stage,
    required String reason,
    String? itemId,
    String? streamUrl,
    int? httpStatus,
    bool transient = false,
    Map<String, Object?> extra = const {},
  }) async {
    if (!Sentry.isEnabled) return;

    final sanitizedUrl = _sanitizeStreamUrl(streamUrl);
    final level = transient ? SentryLevel.warning : SentryLevel.error;

    await Sentry.captureMessage(
      'video playback failed: $reason',
      level: level,
      withScope: (scope) {
        scope
          ..setTag('playback_failure', 'true')
          ..setTag('playback_stage', stage)
          ..setTag('playback_reason', reason);
        if (itemId != null && itemId.isNotEmpty) {
          scope.setTag('item_id', itemId);
        }
        if (httpStatus != null) {
          scope.setTag('http_status', httpStatus.toString());
        }
        if (transient) {
          scope.setTag('transient', 'true');
        }
        scope.setContexts('playback', {
          'stage': stage,
          'reason': reason,
          if (itemId != null && itemId.isNotEmpty) 'item_id': itemId,
          if (sanitizedUrl != null) 'stream_url': sanitizedUrl,
          if (httpStatus != null) 'http_status': httpStatus,
          'transient': transient,
          ...extra,
        });
      },
    );
  }

  static Future<void> reportHttpFailure({
    required String method,
    required String path,
    int? statusCode,
    String? reason,
    Object? exception,
    StackTrace? stackTrace,
    int? elapsedMs,
  }) async {
    if (!Sentry.isEnabled) return;

    final summary = statusCode != null
        ? '$method $path → $statusCode'
        : '$method $path failed';

    if (exception != null) {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) => _applyHttpScope(scope, method, path, statusCode, reason, elapsedMs),
      );
      return;
    }

    await Sentry.captureMessage(
      'playback http: $summary',
      level: SentryLevel.warning,
      withScope: (scope) => _applyHttpScope(scope, method, path, statusCode, reason, elapsedMs),
    );
  }

  static void _applyHttpScope(
    Scope scope,
    String method,
    String path,
    int? statusCode,
    String? reason,
    int? elapsedMs,
  ) {
    scope
      ..setTag('playback_failure', 'true')
      ..setTag('playback_stage', 'http')
      ..setTag('http_method', method);
    if (statusCode != null) {
      scope.setTag('http_status', statusCode.toString());
    }
    if (reason != null && reason.isNotEmpty) {
      scope.setTag('playback_reason', _truncate(reason, 120));
    }
    scope.setContexts('playback_http', {
      'method': method,
      'path': path,
      if (statusCode != null) 'status': statusCode,
      if (reason != null) 'reason': reason,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
    });
  }

  static Future<void> reportStuckPlayback({
    required String itemId,
    String? streamUrl,
    Duration position = Duration.zero,
    Duration? catalogDuration,
    bool nativePlayer = false,
  }) async {
    await reportFailure(
      stage: 'player_stuck',
      reason: 'zero_progress_after_open',
      itemId: itemId,
      streamUrl: streamUrl,
      transient: true,
      extra: {
        'position_ms': position.inMilliseconds,
        if (catalogDuration != null) 'catalog_duration_ms': catalogDuration.inMilliseconds,
        'native_player': nativePlayer,
      },
    );
  }

  static Future<void> reportNativeOpenFailed({
    required String url,
    required int attempt,
    String? itemId,
  }) async {
    await reportFailure(
      stage: 'native_open',
      reason: 'exo_not_ready',
      itemId: itemId,
      streamUrl: url,
      transient: attempt < 3,
      extra: {'attempt': attempt},
    );
  }

  static String? _sanitizeStreamUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final q = Map<String, String>.from(uri.queryParameters)..remove('token')..remove('api_key');
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }
}
