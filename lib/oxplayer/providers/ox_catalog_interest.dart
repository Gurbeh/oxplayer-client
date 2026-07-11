import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/oxplayer_catalog_http.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_watchlist_dashboard.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/providers/api_provider.dart';

part 'ox_catalog_interest.g.dart';

class OxCatalogInterestState {
  const OxCatalogInterestState({
    this.following = false,
    this.watchlisted = false,
  });

  final bool following;
  final bool watchlisted;

  static const empty = OxCatalogInterestState();

  OxCatalogInterestState copyWith({bool? following, bool? watchlisted}) {
    return OxCatalogInterestState(
      following: following ?? this.following,
      watchlisted: watchlisted ?? this.watchlisted,
    );
  }
}

@riverpod
class OxCatalogInterest extends _$OxCatalogInterest {
  @override
  Future<OxCatalogInterestState> build(String catalogId) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return OxCatalogInterestState.empty;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return OxCatalogInterestState.empty;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return OxCatalogInterestState.empty;

    final uri = Uri.parse('$baseUrl/me/catalog-interests/$catalogId');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        'GET ${uri.path} failed status=${response.statusCode}',
        name: 'OxCatalogInterest',
      );
      return OxCatalogInterestState.empty;
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return OxCatalogInterestState.empty;
    return OxCatalogInterestState(
      following: body['following'] == true,
      watchlisted: body['watchlisted'] == true,
    );
  }

  Future<bool> setFollowing(bool following) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final uri = Uri.parse('$baseUrl/me/follows/$catalogId');
    final response = following
        ? await http.put(uri, headers: headers)
        : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${following ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'OxCatalogInterest',
      );
      return false;
    }
    final current = state.value ?? OxCatalogInterestState.empty;
    state = AsyncData(current.copyWith(following: following));
    return true;
  }

  Future<bool> setWatchlisted(bool watchlisted) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    if (baseUrl == null || baseUrl.isEmpty) return false;
    final headers = oxCatalogApiHeaders(ref);
    if (headers.isEmpty) return false;

    final uri = Uri.parse('$baseUrl/me/watchlist/$catalogId');
    final response = watchlisted
        ? await http.put(uri, headers: headers)
        : await http.delete(uri, headers: headers);
    if (response.statusCode != 200) {
      developer.log(
        '${watchlisted ? 'PUT' : 'DELETE'} ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'OxCatalogInterest',
      );
      return false;
    }
    final current = state.value ?? OxCatalogInterestState.empty;
    state = AsyncData(current.copyWith(watchlisted: watchlisted));
    oxResetWatchlistHomeFeedRef(ref);
    ref.invalidate(oxWatchlistDashboardProvider);
    unawaited(ref.read(viewsProvider.notifier).fetchViews());
    return true;
  }

  Future<bool> toggleFollowing() async {
    final current = await future;
    return setFollowing(!current.following);
  }

  Future<bool> toggleWatchlisted() async {
    final current = await future;
    return setWatchlisted(!current.watchlisted);
  }
}
