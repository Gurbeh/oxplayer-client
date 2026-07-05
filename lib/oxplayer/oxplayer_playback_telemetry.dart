import 'package:flutter/foundation.dart';
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
    bool transient = false,
  }) async {
    if (!Sentry.isEnabled) return;

    final summary = statusCode != null
        ? '$method $path → $statusCode'
        : '$method $path failed';

    if (exception != null) {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) => _applyHttpScope(scope, method, path, statusCode, reason, elapsedMs, transient),
      );
      return;
    }

    await Sentry.captureMessage(
      'playback http: $summary',
      level: transient ? SentryLevel.warning : SentryLevel.warning,
      withScope: (scope) => _applyHttpScope(scope, method, path, statusCode, reason, elapsedMs, transient),
    );
  }

  static void _applyHttpScope(
    Scope scope,
    String method,
    String path,
    int? statusCode,
    String? reason,
    int? elapsedMs,
    bool transient,
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
    if (transient) {
      scope.setTag('transient', 'true');
    }
    scope.setContexts('playback_http', {
      'method': method,
      'path': path,
      if (statusCode != null) 'status': statusCode,
      if (reason != null) 'reason': reason,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      'transient': transient,
    });
  }

  static Future<void> reportStuckPlayback({
    required String itemId,
    String? streamUrl,
    Duration position = Duration.zero,
    Duration? catalogDuration,
    bool nativePlayer = false,
    String stuckKind = 'start',
    bool transient = true,
  }) async {
    await reportFailure(
      stage: 'player_stuck',
      reason: stuckKind == 'mid_stream' ? 'mid_stream_frozen' : 'zero_progress_after_open',
      itemId: itemId,
      streamUrl: streamUrl,
      transient: transient,
      extra: {
        'position_ms': position.inMilliseconds,
        if (catalogDuration != null) 'catalog_duration_ms': catalogDuration.inMilliseconds,
        'native_player': nativePlayer,
        'stuck_kind': stuckKind,
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
      transient: attempt < 4,
      extra: {'attempt': attempt},
    );
  }

  static DateTime? _lastVolumeAnomalyAt;
  static String? _lastVolumeAnomalyReason;

  /// Detects MPV play/pause fade leaving audio muted (intermittent on Android).
  /// Not marked transient so events reach Sentry for trend monitoring.
  static Future<void> reportVolumeAnomaly({
    required String reason,
    required double playerVolume,
    required double preferredVolume,
    bool enablePlayPauseFade = false,
    bool fadeAborted = false,
  }) async {
    if (!Sentry.isEnabled) return;

    final now = DateTime.now();
    if (_lastVolumeAnomalyReason == reason &&
        _lastVolumeAnomalyAt != null &&
        now.difference(_lastVolumeAnomalyAt!) < const Duration(minutes: 5)) {
      return;
    }
    _lastVolumeAnomalyAt = now;
    _lastVolumeAnomalyReason = reason;

    await Sentry.captureMessage(
      'playback volume anomaly: $reason',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope
          ..setTag('playback_anomaly', 'true')
          ..setTag('playback_stage', 'player_volume')
          ..setTag('playback_reason', reason);
        scope.setContexts('playback_volume', {
          'reason': reason,
          'player_volume': playerVolume,
          'preferred_volume': preferredVolume,
          'enable_play_pause_fade': enablePlayPauseFade,
          if (fadeAborted) 'fade_aborted': fadeAborted,
        });
      },
    );
  }

  /// Test-only reset for dedupe window.
  @visibleForTesting
  static void resetVolumeAnomalyDedupeForTest() {
    _lastVolumeAnomalyAt = null;
    _lastVolumeAnomalyReason = null;
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
