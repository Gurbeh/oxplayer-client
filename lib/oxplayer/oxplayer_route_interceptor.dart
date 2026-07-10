import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_selector.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/providers/api_provider.dart';

/// On HTTP 451 or connection failure to global CDN, flips to Iran edge and retries once.
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
      try {
        final response = await chain.proceed(chain.request);

        if (response.statusCode != 451 || routeRetries >= _maxRouteRetries) {
          return response;
        }
        if (!_isOxRouteRequired(response)) {
          return response;
        }
        if (OxplayerRoute.active == OxplayerEdge.iran) {
          return response;
        }

        await _flipToIran();
        routeRetries++;
      } on IOException catch (e) {
        if (!_shouldFlipOnConnectionError(e) || routeRetries >= _maxRouteRetries) {
          rethrow;
        }
        await _flipToIran();
        routeRetries++;
      }
    }
  }

  Future<void> _flipToIran() async {
    await OxplayerRouteSelector.switchTo(OxplayerEdge.iran);
    OxplayerStreamNodesApi.invalidateCache();
    ref.invalidate(serverUrlProvider);
  }

  bool _shouldFlipOnConnectionError(IOException error) {
    if (!OxplayerRouteEnv.hasIranRoute || OxplayerRoute.active == OxplayerEdge.iran) {
      return false;
    }
    final global = OxplayerRouteEnv.globalApiBaseUrl;
    if (global == null || global.isEmpty) return true;
    final host = Uri.tryParse(global)?.host.toLowerCase();
    if (host == null || host.isEmpty) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains(host) || msg.contains('api.oxplayer.app');
  }

  bool _isOxRouteRequired(Response<dynamic> response) {
    final header = response.headers['x-ox-route-required'] ?? response.headers['X-Ox-Route-Required'];
    if (header != null && _isIranRouteHeader(header)) {
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

  bool _isIranRouteHeader(String header) {
    switch (header.trim().toLowerCase()) {
      case 'iran':
      case 'arvan':
        return true;
      default:
        return false;
    }
  }
}
