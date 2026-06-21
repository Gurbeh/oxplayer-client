import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';

/// Sentry performance spans for Jellyfin/OX HTTP (non-playback-specific).
class OxplayerHttpPerformanceInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (!OxplayerEnv.isEnabled || !Sentry.isEnabled) {
      return chain.proceed(chain.request);
    }

    final request = chain.request;
    final path = _safePath(request.url);
    final description = '${request.method} $path';

    final parent = Sentry.getSpan();
    final span = parent?.startChild('http.client', description: description) ??
        Sentry.startTransaction('http.client', description, bindToScope: true);

    try {
      final response = await chain.proceed(request);
      span
        ..setData('http.method', request.method)
        ..setData('http.path', path)
        ..setData('http.status_code', response.statusCode)
        ..status = SpanStatus.fromHttpStatusCode(response.statusCode);
      return response;
    } catch (error, stackTrace) {
      span
        ..throwable = error
        ..status = const SpanStatus.internalError();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await span.finish();
    }
  }

  static String _safePath(Uri url) {
    final path = url.path;
    if (path.isEmpty) return '/';
    return path.length > 120 ? '${path.substring(0, 120)}…' : path;
  }
}
