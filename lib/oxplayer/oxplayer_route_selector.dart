import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_store.dart';

/// Startup edge resolution: global (Cloudflare → Hetzner) unless Iran enforce blocks it.
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

    // Iran web entrypoint: always Arvan oxplayer.ir (ignore global probe / stale kabazhe builds).
    if (kIsWeb && _isOxplayerIranWebHost()) {
      OxplayerRoute.setActive(OxplayerEdge.arvan);
      final prefs = await SharedPreferences.getInstance();
      await OxplayerRouteStore(prefs).saveEdge(OxplayerEdge.arvan);
      return;
    }

    if (!OxplayerRouteEnv.hasArvanRoute) {
      OxplayerRoute.setActive(OxplayerEdge.global);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final store = OxplayerRouteStore(prefs);
    final stored = store.readEdge();

    final global = OxplayerRouteEnv.globalApiBaseUrl;
    final arvan = OxplayerRouteEnv.arvanApiBaseUrl;
    if (global == null && arvan == null) return;

    final probes = await Future.wait([
      if (global != null) _probeHealth(global, edge: OxplayerEdge.global),
      if (arvan != null) _probeHealth(arvan, edge: OxplayerEdge.arvan),
    ]);

    final healthy = <OxplayerEdge, bool>{
      for (final p in probes) p.edge: p.ok,
    };

    final globalOk = healthy[OxplayerEdge.global] == true;
    final arvanOk = healthy[OxplayerEdge.arvan] == true;
    final globalBlocked = global != null && globalOk && await _globalPathBlocked(global);

    final OxplayerEdge chosen;
    if (globalOk && !globalBlocked) {
      // Outside Iran: always global CDN → Hetzner (ignore stored arvan from a past Iran session).
      chosen = OxplayerEdge.global;
    } else if (arvanOk) {
      chosen = OxplayerEdge.arvan;
    } else if (!globalOk && OxplayerRouteEnv.hasArvanRoute) {
      // Iran hard-blocks Cloudflare (TCP refused) — global probe fails; try Arvan vanity.
      chosen = OxplayerEdge.arvan;
    } else if (globalOk) {
      // Iran with Arvan down — start on global; 451 interceptor flips when enforce responds.
      chosen = OxplayerEdge.global;
    } else {
      chosen = stored ?? OxplayerEdge.global;
    }

    OxplayerRoute.setActive(chosen);
    await store.saveEdge(chosen);
  }

  static Future<({OxplayerEdge edge, bool ok})> _probeHealth(String baseUrl, {required OxplayerEdge edge}) async {
    try {
      final pin = edge == OxplayerEdge.arvan ? OxplayerRouteEnv.arvanEdgeAddr : null;
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
      return (edge: edge, ok: response.statusCode >= 200 && response.statusCode < 500);
    } catch (_) {
      return (edge: edge, ok: false);
    }
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
      if (header != null && header.trim().toLowerCase() == 'arvan') return true;
      return response.body.contains('ox_route_required');
    } catch (_) {
      return false;
    }
  }

  static bool _isOxplayerIranWebHost() {
    final host = Uri.base.host.toLowerCase();
    return host == 'oxplayer.ir' || host == 'www.oxplayer.ir';
  }
}
