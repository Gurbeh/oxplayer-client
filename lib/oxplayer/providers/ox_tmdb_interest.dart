import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/providers/ox_watchlist_dashboard.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

part 'ox_tmdb_interest.g.dart';

class OxTmdbInterestState {
  final bool following;
  final bool watchlisted;
  final bool favorited;

  const OxTmdbInterestState({
    this.following = false,
    this.watchlisted = false,
    this.favorited = false,
  });
}

String oxSeerrMediaTypeApiValue(SeerrMediaType type) {
  return switch (type) {
    SeerrMediaType.movie => 'movie',
    SeerrMediaType.tvshow => 'tv',
    _ => 'movie',
  };
}

Map<String, String> _oxAuthHeaders(OxplayerRead read) {
  final credentials = read(userProvider)?.credentials;
  if (credentials == null) return const {};
  return {
    ...oxplayerMediaBrowserHeaders(read, credentials),
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}

@riverpod
class OxTmdbInterest extends _$OxTmdbInterest {
  @override
  Future<OxTmdbInterestState> build(int tmdbId, SeerrMediaType mediaType) async {
    if (!OxplayerEnv.isEnabled || tmdbId <= 0) {
      return const OxTmdbInterestState();
    }
    final baseUrl = ref.read(serverUrlProvider);
    final credentials = ref.read(userProvider)?.credentials;
    if (baseUrl == null || baseUrl.isEmpty || credentials == null || credentials.token.trim().isEmpty) {
      return const OxTmdbInterestState();
    }

    final apiMedia = oxSeerrMediaTypeApiValue(mediaType);
    final uri = Uri.parse('$baseUrl/me/tmdb-interests/$apiMedia/$tmdbId');
    final response = await http.get(uri, headers: _oxAuthHeaders(ref.read));
    if (response.statusCode != 200) {
      developer.log(
        'GET ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'OxTmdbInterest',
      );
      return const OxTmdbInterestState();
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return const OxTmdbInterestState();
    return OxTmdbInterestState(
      following: body['following'] == true,
      watchlisted: body['watchlisted'] == true,
      favorited: body['favorited'] == true,
    );
  }

  Future<bool> setFollowing(bool following, {String title = '', String posterUrl = ''}) {
    return _patch(following: following, title: title, posterUrl: posterUrl);
  }

  Future<bool> setWatchlisted(bool watchlisted, {String title = '', String posterUrl = ''}) {
    return _patch(watchlisted: watchlisted, title: title, posterUrl: posterUrl);
  }

  Future<bool> setFavorited(bool favorited, {String title = '', String posterUrl = ''}) {
    return _patch(favorited: favorited, title: title, posterUrl: posterUrl);
  }

  Future<bool> _patch({
    bool? following,
    bool? watchlisted,
    bool? favorited,
    String title = '',
    String posterUrl = '',
  }) async {
    if (!OxplayerEnv.isEnabled || tmdbId <= 0) return false;
    final baseUrl = ref.read(serverUrlProvider);
    final credentials = ref.read(userProvider)?.credentials;
    if (baseUrl == null || baseUrl.isEmpty || credentials == null || credentials.token.trim().isEmpty) {
      return false;
    }

    final apiMedia = oxSeerrMediaTypeApiValue(mediaType);
    final uri = Uri.parse('$baseUrl/me/tmdb-interests/$apiMedia/$tmdbId');
    final payload = <String, dynamic>{
      if (following != null) 'following': following,
      if (watchlisted != null) 'watchlisted': watchlisted,
      if (favorited != null) 'favorited': favorited,
      if (title.isNotEmpty) 'title': title,
      if (posterUrl.isNotEmpty) 'posterUrl': posterUrl,
    };
    final response = await http.put(
      uri,
      headers: _oxAuthHeaders(ref.read),
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      developer.log(
        'PUT ${uri.path} failed status=${response.statusCode} body=${response.body}',
        name: 'OxTmdbInterest',
      );
      return false;
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return false;
    state = AsyncData(
      OxTmdbInterestState(
        following: body['following'] == true,
        watchlisted: body['watchlisted'] == true,
        favorited: body['favorited'] == true,
      ),
    );
    if (watchlisted != null) {
      ref.invalidate(oxWatchlistDashboardProvider);
    }
    return true;
  }
}
