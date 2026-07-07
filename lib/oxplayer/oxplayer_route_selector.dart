import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_store.dart';

/// Startup edge resolution: env override → stored preference → parallel /health probe.
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

    OxplayerEdge chosen;
    if (stored != null && healthy[stored] == true) {
      chosen = stored;
    } else if (healthy[OxplayerEdge.arvan] == true && healthy[OxplayerEdge.global] != true) {
      chosen = OxplayerEdge.arvan;
    } else if (healthy[OxplayerEdge.global] == true) {
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
}
