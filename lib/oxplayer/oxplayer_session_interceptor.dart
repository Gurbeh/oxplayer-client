import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/user_provider.dart';

/// On 401, tries refresh once; otherwise clears the local session and routes to login.
class OxplayerSessionInterceptor implements Interceptor {
  OxplayerSessionInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final response = await chain.proceed(chain.request);

    if (response.statusCode != 401) return response;

    final path = chain.request.url.path.toLowerCase();
    if (path.contains('authenticatebyname')) return response;

    if (ref.read(userProvider) == null) return response;

    bool refreshed = false;
    try {
      refreshed = await oxplayerTryRefreshSession(ref.read);
    } catch (_) {
      // Transient network / API restart — do not clear the session.
      return response;
    }
    if (refreshed) {
      final retry = oxplayerRetryRequestWithFreshToken(ref, chain.request);
      return chain.proceed(retry);
    }

    // Refresh failed without clearing the session (transient 5xx) — surface the 401, keep local tokens.
    if (ref.read(userProvider) == null) {
      ref.read(oxplayerSessionRevokedProvider.notifier).state++;
    }
    return response;
  }
}

/// Re-applies the current access token after a successful refresh (upstream [JellyRequest] is not re-run).
Request oxplayerRetryRequestWithFreshToken(Ref ref, Request request) {
  final credentials = ref.read(userProvider)?.credentials;
  if (credentials == null || credentials.token.trim().isEmpty) {
    return request;
  }
  final headers = Map<String, String>.from(request.headers);
  headers.addAll(oxplayerMediaBrowserHeaders(ref.read, credentials));
  return request.copyWith(headers: headers);
}
