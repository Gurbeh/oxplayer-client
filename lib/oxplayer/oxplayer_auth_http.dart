import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_hints.dart';
import 'package:fladder/oxplayer/oxplayer_route_selector.dart';

/// Route-aware HTTP for pre-login auth endpoints (/auth/*).
abstract final class OxplayerAuthHttp {
  static String? get baseUrl =>
      OxplayerRoute.connectBaseUrl ??
      OxplayerRoute.apiBaseUrl ??
      OxplayerEnv.apiBaseUrl;

  static Map<String, String> headers({Map<String, String>? extra}) {
    return {
      ...OxplayerRoute.connectHeaders,
      if (OxplayerRoute.active == OxplayerEdge.iran) 'X-Ox-Edge': 'iran',
      ...?extra,
    };
  }

  static Uri uri(String path, [Map<String, String>? query]) {
    final base = baseUrl;
    if (base == null) {
      throw StateError('OXPLAYER API base is not configured');
    }
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  static Future<http.Response> send(Future<http.Response> Function() request) async {
    var routeRetries = 0;
    while (true) {
      final response = await request();
      if (routeRetries >= 1 || !_shouldFlipToIran(response)) {
        return response;
      }
      await OxplayerRouteSelector.switchTo(OxplayerEdge.iran);
      routeRetries++;
    }
  }

  static bool _shouldFlipToIran(http.Response response) {
    if (response.statusCode != 451) return false;
    if (OxplayerRoute.active == OxplayerEdge.iran) return false;
    if (!OxplayerRouteEnv.hasIranRoute) return false;
    if (OxplayerRouteHints.headersRequireIranRoute(response.headers)) return true;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] == 'ox_route_required') return true;
    } catch (_) {}
    return response.body.contains('ox_route_required');
  }
}
