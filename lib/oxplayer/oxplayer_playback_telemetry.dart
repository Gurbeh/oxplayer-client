import 'package:sentry_flutter/sentry_flutter.dart';

/// Reports video playback failures to Sentry (stream URL tokens are stripped).
abstract final class OxplayerPlaybackTelemetry {
  static Future<void> reportFailure({
    required String stage,
    required String reason,
    String? itemId,
    String? streamUrl,
    int? httpStatus,
    bool transient = false,
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
        });
      },
    );
  }

  static String? _sanitizeStreamUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final q = Map<String, String>.from(uri.queryParameters)..remove('token')..remove('api_key');
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  }
}
