import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/oxplayer/oxplayer_route.dart';

/// Persists last-known-good CDN edge across app restarts.
class OxplayerRouteStore {
  OxplayerRouteStore(this._prefs);

  final SharedPreferences _prefs;

  static const _keyEdge = 'ox_route_edge';

  OxplayerEdge? readEdge() {
    final raw = _prefs.getString(_keyEdge)?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    return OxplayerEdge.tryParse(raw);
  }

  Future<void> saveEdge(OxplayerEdge edge) async {
    await _prefs.setString(_keyEdge, edge.name);
  }

  Future<void> clear() async {
    await _prefs.remove(_keyEdge);
  }
}
