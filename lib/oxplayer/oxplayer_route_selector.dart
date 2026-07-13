import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_hints.dart';
import 'package:fladder/oxplayer/oxplayer_route_store.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';

/// Startup edge resolution: global outside Iran; Iran .ir API + stream inside Iran.
abstract final class OxplayerRouteSelector {
  static const _probeTimeout = Duration(seconds: 2);

  static Future<void> resolveAtStartup() async {
    if (!OxplayerConfig.isEnabled) return;
    await OxplayerDotenv.ensureLoaded();

    final forced = OxplayerRouteEnv.forceEdge;
    if (forced != null) {
      final edge = OxplayerEdge.tryParse(forced);
      if (edge != null) {
        OxplayerRoute.setActive(edge);
        return;
      }
    }

    // Iran web entrypoint: always .ir hosts (ignore global probe / stale kabazhe builds).
    if (kIsWeb && _isOxplayerIranWebHost()) {
      OxplayerRoute.setActive(OxplayerEdge.iran);
      final prefs = await SharedPreferences.getInstance();
      await OxplayerRouteStore(prefs).saveEdge(OxplayerEdge.iran);
      return;
    }

    final global = OxplayerRouteEnv.globalApiBaseUrl;

    // Local dev API (localhost / LAN) — never dual-edge probe into production Iran.
    if (global != null && _isLocalDevApiUrl(global)) {
      OxplayerRoute.setActive(OxplayerEdge.global);
      return;
    }

    if (!OxplayerRouteEnv.hasIranRoute) {
      OxplayerRoute.setActive(OxplayerEdge.global);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final store = OxplayerRouteStore(prefs);
    final stored = store.readEdge();
    final iran = OxplayerRouteEnv.iranApiBaseUrl;
    if (global == null && iran == null) return;

    final probes = await Future.wait([
      if (global != null) _probeHealth(global, edge: OxplayerEdge.global),
      if (iran != null) _probeHealth(iran, edge: OxplayerEdge.iran),
    ]);

    final healthy = <OxplayerEdge, bool>{
      for (final p in probes) p.edge: p.ok,
    };

    ({OxplayerEdge edge, bool ok, bool iranRouteHint})? globalProbe;
    for (final p in probes) {
      if (p.edge == OxplayerEdge.global) {
        globalProbe = p;
        break;
      }
    }
    final globalOk = healthy[OxplayerEdge.global] == true;
    final iranOk = healthy[OxplayerEdge.iran] == true;
    final globalBlocked = global != null && globalOk && await _globalPathBlocked(global);
    final iranRouteRequired = globalBlocked || (globalProbe?.iranRouteHint ?? false);

    final OxplayerEdge chosen;
    if (iranRouteRequired && iranOk) {
      chosen = OxplayerEdge.iran;
    } else if (globalOk && !iranRouteRequired) {
      chosen = OxplayerEdge.global;
    } else if (iranOk) {
      chosen = OxplayerEdge.iran;
    } else if (!globalOk && OxplayerRouteEnv.hasIranRoute) {
      chosen = OxplayerEdge.iran;
    } else if (globalOk) {
      chosen = OxplayerEdge.global;
    } else {
      chosen = stored ?? OxplayerEdge.global;
    }

    OxplayerRoute.setActive(chosen);
    await store.saveEdge(chosen);
    OxplayerStreamLog.event('route_resolve', fields: {
      'edge': chosen.name,
      'api': OxplayerRoute.apiBaseUrl,
      'streamVanity': OxplayerRoute.streamBaseUrl,
      'iranRouteRequired': iranRouteRequired,
      'globalOk': globalOk,
      'iranOk': iranOk,
      'globalBlocked': globalBlocked,
    });
  }

  static Future<({OxplayerEdge edge, bool ok, bool iranRouteHint})> _probeHealth(
    String baseUrl, {
    required OxplayerEdge edge,
  }) async {
    try {
      final pin = edge == OxplayerEdge.iran ? OxplayerRouteEnv.iranEdgeAddr : null;
      var uri = Uri.parse('$baseUrl/health');
      final headers = <String, String>{};
      if (pin != null && pin.isNotEmpty) {
        uri = uri.replace(host: pin);
        final logicalHost = Uri.tryParse(baseUrl)?.host;
        if (logicalHost != null && logicalHost.isNotEmpty) {
          headers['Host'] = logicalHost;
        }
      }

      final response = await http.get(uri, headers: headers).timeout(_probeTimeout);
      final ok = response.statusCode >= 200 && response.statusCode < 500;
      final iranRouteHint = edge == OxplayerEdge.global && ok && _responseIndicatesIranRoute(response);
      return (edge: edge, ok: ok, iranRouteHint: iranRouteHint);
    } catch (_) {
      return (edge: edge, ok: false, iranRouteHint: false);
    }
  }

  static bool _responseIndicatesIranRoute(http.Response response) {
    return OxplayerRouteHints.headersRequireIranRoute(response.headers);
  }

  static Future<void> switchTo(OxplayerEdge edge) async {
    OxplayerRoute.setActive(edge);
    final prefs = await SharedPreferences.getInstance();
    await OxplayerRouteStore(prefs).saveEdge(edge);
  }

  /// True when Iran enforce returns 451 on global CDN (/health is exempt).
  static Future<bool> _globalPathBlocked(String globalBase) async {
    try {
      final response = await http
          .get(Uri.parse('${globalBase.replaceAll(RegExp(r'/+$'), '')}/ox/client/android-update'))
          .timeout(_probeTimeout);
      if (response.statusCode != 451) return false;
      final header = response.headers['x-ox-route-required'];
      if (header != null && OxplayerRouteHints.isIranRouteRequiredHeader(header)) return true;
      return response.body.contains('ox_route_required');
    } catch (_) {
      return false;
    }
  }

  static bool _isLocalDevApiUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final h = uri.host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '::1' || h == '10.0.2.2') {
      return true;
    }
    final parts = h.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((n) => n == null)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    return a == 172 && b >= 16 && b <= 31;
  }

  static bool _isOxplayerIranWebHost() {
    final host = Uri.base.host.toLowerCase();
    return host == 'oxplayer.ir' ||
        host == 'www.oxplayer.ir' ||
        host == 'web.oxplayer.ir' ||
        host.endsWith('.ir.cdn.ir');
  }
}
