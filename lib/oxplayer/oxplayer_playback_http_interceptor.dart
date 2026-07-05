import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';

/// Records playback-related Jellyfin/OX HTTP to Sentry (breadcrumbs + failures).
class OxplayerPlaybackHttpInterceptor implements Interceptor {
  OxplayerPlaybackHttpInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (!OxplayerEnv.isEnabled) return chain.proceed(chain.request);

    final request = chain.request;
    if (!_isPlaybackRequest(request)) return chain.proceed(request);

    final started = DateTime.now();
    final path = _safePath(request.url);
    final method = request.method;

    try {
      final response = await chain.proceed(request);
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;

      await _addBreadcrumb(
        message: '$method $path → ${response.statusCode}',
        data: {
          'method': method,
          'path': path,
          'status': response.statusCode,
          'elapsed_ms': elapsedMs,
        },
        level: response.isSuccessful ? SentryLevel.info : SentryLevel.warning,
      );

      if (!response.isSuccessful) {
        final reason = response.error?.toString() ?? response.base.reasonPhrase ?? 'http_error';
        unawaited(OxplayerPlaybackTelemetry.reportHttpFailure(
          method: method,
          path: path,
          statusCode: response.statusCode,
          reason: reason,
          elapsedMs: elapsedMs,
          transient: _isTransientPlaybackHttpFailure(response.statusCode, reason),
        ));
      }

      return response;
    } catch (e, st) {
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      unawaited(OxplayerPlaybackTelemetry.reportHttpFailure(
        method: method,
        path: path,
        reason: e.runtimeType.toString(),
        exception: e,
        stackTrace: st,
        elapsedMs: elapsedMs,
      ));
      rethrow;
    }
  }

  static bool _isPlaybackRequest(Request request) {
    final path = request.url.path.toLowerCase();
    if (path.contains('playbackinfo')) return true;
    if (path.contains('/videos/') && path.contains('stream')) return true;
    if (path.contains('/sessions/playing')) return true;
    if (path.contains('/stream-nodes')) return true;
    if (path.contains('/me/stream')) return true;
    return false;
  }

  static bool _isTransientPlaybackHttpFailure(int statusCode, String reason) {
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) return true;
    if (statusCode == 404 && reason.toLowerCase().contains('no playable media')) return true;
    return false;
  }

  static String _safePath(Uri url) {
    final segments = url.pathSegments;
    final sanitized = segments.map((s) {
      if (RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(s)) return '{id}';
      if (RegExp(r'^v/\d+').hasMatch(s)) return 'v/{variant}';
      if (RegExp(r'^\d+$').hasMatch(s)) return '{num}';
      return s;
    }).join('/');
    final q = Map<String, String>.from(url.queryParameters)..remove('token')..remove('api_key');
    if (q.isEmpty) return '/$sanitized';
    return '/$sanitized?${q.keys.join(',')}';
  }

  static Future<void> _addBreadcrumb({
    required String message,
    required Map<String, Object?> data,
    required SentryLevel level,
  }) async {
    if (!Sentry.isEnabled) return;
    await Sentry.addBreadcrumb(Breadcrumb(
      message: message,
      level: level,
      category: 'playback.http',
      data: data,
    ));
  }
}
