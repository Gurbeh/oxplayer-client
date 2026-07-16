import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/oxplayer_catalog_http.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_watchlist_dashboard.dart';
import 'package:fladder/providers/api_provider.dart';

part 'ox_item_flags.g.dart';

class OxItemFlagsState {
  const OxItemFlagsState({
    this.favoriteIds = const {},
    this.playedIds = const {},
    this.watchlistIds = const {},
    this.followingIds = const {},
    this.loaded = false,
  });

  final Set<String> favoriteIds;
  final Set<String> playedIds;
  final Set<String> watchlistIds;
  final Set<String> followingIds;
  final bool loaded;

  static const empty = OxItemFlagsState();

  bool isFavorite(String id) => favoriteIds.contains(id);
  bool isPlayed(String id) => playedIds.contains(id);
  bool isWatchlisted(String id) => watchlistIds.contains(id);
  bool isFollowing(String id) => followingIds.contains(id);

  OxItemFlagsState copyWith({
    Set<String>? favoriteIds,
    Set<String>? playedIds,
    Set<String>? watchlistIds,
    Set<String>? followingIds,
    bool? loaded,
  }) {
    return OxItemFlagsState(
      favoriteIds: favoriteIds ?? this.favoriteIds,
      playedIds: playedIds ?? this.playedIds,
      watchlistIds: watchlistIds ?? this.watchlistIds,
      followingIds: followingIds ?? this.followingIds,
      loaded: loaded ?? this.loaded,
    );
  }
}

Set<String> _idsFromJson(dynamic raw) {
  if (raw is! List) return {};
  return {
    for (final e in raw)
      if (e is String && e.isNotEmpty) e,
  };
}

@Riverpod(keepAlive: true)
class OxItemFlags extends _$OxItemFlags {
  @override
  OxItemFlagsState build() => OxItemFlagsState.empty;

  Future<void> load() async {
    if (!OxplayerEnv.isEnabled) return;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return;

    final uri = Uri.parse('$baseUrl/me/item-flags');
    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) {
        developer.log(
          'GET ${uri.path} failed status=${response.statusCode}',
          name: 'OxItemFlags',
        );
        return;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return;
      state = OxItemFlagsState(
        favoriteIds: _idsFromJson(body['favoriteIds']),
        playedIds: _idsFromJson(body['playedIds']),
        watchlistIds: _idsFromJson(body['watchlistIds']),
        followingIds: _idsFromJson(body['followingIds']),
        loaded: true,
      );
    } catch (e, st) {
      developer.log('GET /me/item-flags failed', name: 'OxItemFlags', error: e, stackTrace: st);
    }
  }

  void setFavorite(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.favoriteIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(favoriteIds: next);
  }

  void setPlayed(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.playedIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(playedIds: next);
  }

  void setWatchlisted(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.watchlistIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(watchlistIds: next);
  }

  void setFollowing(String id, bool value) {
    if (id.isEmpty) return;
    final next = {...state.followingIds};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(followingIds: next);
  }

  Future<bool> toggleFollowing(String catalogId) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final next = !state.isFollowing(catalogId);
    final uri = Uri.parse('$baseUrl/me/follows/$catalogId');
    final response = next ? await http.put(uri, headers: headers) : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${next ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode}',
        name: 'OxItemFlags',
      );
      return false;
    }
    setFollowing(catalogId, next);
    return true;
  }

  Future<bool> toggleWatchlisted(String catalogId) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final next = !state.isWatchlisted(catalogId);
    final uri = Uri.parse('$baseUrl/me/watchlist/$catalogId');
    final response = next ? await http.put(uri, headers: headers) : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${next ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode}',
        name: 'OxItemFlags',
      );
      return false;
    }
    setWatchlisted(catalogId, next);
    oxResetWatchlistHomeFeedRef(ref);
    ref.invalidate(oxWatchlistDashboardProvider);
    return true;
  }

  void clear() => state = OxItemFlagsState.empty;
}
