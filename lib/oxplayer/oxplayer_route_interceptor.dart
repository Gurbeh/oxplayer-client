import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_selector.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/providers/api_provider.dart';

/// On HTTP 451 `ox_route_required`, flips to Arvan edge and retries once.
class OxplayerRouteInterceptor implements Interceptor {
  OxplayerRouteInterceptor(this.ref);

  final Ref ref;

  static const _maxRouteRetries = 1;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    if (!OxplayerConfig.isEnabled) {
      return chain.proceed(chain.request);
    }

    var routeRetries = 0;

    while (true) {
      final response = await chain.proceed(chain.request);

      if (response.statusCode != 451 || routeRetries >= _maxRouteRetries) {
        return response;
      }
      if (!_isOxRouteRequired(response)) {
        return response;
      }
      if (OxplayerRoute.active == OxplayerEdge.arvan) {
        return response;
      }

      await OxplayerRouteSelector.switchTo(OxplayerEdge.arvan);
      OxplayerStreamNodesApi.invalidateCache();
      ref.invalidate(serverUrlProvider);
      routeRetries++;
    }
  }

  bool _isOxRouteRequired(Response<dynamic> response) {
    final header = response.headers['x-ox-route-required'] ?? response.headers['X-Ox-Route-Required'];
    if (header != null && header.trim().toLowerCase() == 'arvan') {
      return true;
    }

    final body = response.body;
    if (body is Map && body['error'] == 'ox_route_required') {
      return true;
    }

    final raw = response.bodyString;
    if (raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['error'] == 'ox_route_required') {
        return true;
      }
    } catch (_) {}
    return false;
  }
}
