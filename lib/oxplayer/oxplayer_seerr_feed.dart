import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_catalog_http.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// Parsed Seerr home shelves from GET /seerr/proxy/api/v1/discover/dashboard-feed.
class OxSeerrFeedResult {
  const OxSeerrFeedResult({
    this.trending = const [],
    this.popularMovies = const [],
    this.popularSeries = const [],
    this.expectedMovies = const [],
    this.expectedSeries = const [],
    this.catalogAvailableMovies = const [],
    this.catalogAvailableSeries = const [],
    this.recentlyAdded = const [],
  });

  final List<SeerrDashboardPosterModel> trending;
  final List<SeerrDashboardPosterModel> popularMovies;
  final List<SeerrDashboardPosterModel> popularSeries;
  final List<SeerrDashboardPosterModel> expectedMovies;
  final List<SeerrDashboardPosterModel> expectedSeries;
  final List<SeerrDashboardPosterModel> catalogAvailableMovies;
  final List<SeerrDashboardPosterModel> catalogAvailableSeries;
  final List<SeerrDashboardPosterModel> recentlyAdded;
}

abstract final class OxplayerSeerrFeed {
  /// One HTTP round-trip for discover shelves + OX catalog rows + recently added.
  static Future<OxSeerrFeedResult?> fetch(Ref ref) async {
    final creds = ref.read(userProvider)?.seerrCredentials;
    final base = creds?.serverUrl.trim();
    if (!OxplayerEnv.isEnabled || base == null || base.isEmpty || creds?.useProxy != true) {
      return null;
    }

    final uri = Uri.parse('$base/api/v1/discover/dashboard-feed');
    final headers = oxCatalogApiHeaders(ref);

    http.Response response;
    try {
      response = await http.get(uri, headers: headers);
    } catch (_) {
      return null;
    }

    if (response.statusCode == 404 || response.statusCode == 405) {
      return null;
    }
    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;

    final api = ref.read(seerrApiProvider);
    return OxSeerrFeedResult(
      trending: _posters(api, body['Trending']),
      popularMovies: _posters(api, body['PopularMovies']),
      popularSeries: _posters(api, body['PopularSeries']),
      expectedMovies: _posters(api, body['ExpectedMovies']),
      expectedSeries: _posters(api, body['ExpectedSeries']),
      catalogAvailableMovies: _posters(api, body['CatalogMovies']),
      catalogAvailableSeries: _posters(api, body['CatalogSeries']),
      recentlyAdded: _posters(api, body['RecentlyAdded']),
    );
  }

  static List<SeerrDashboardPosterModel> _posters(
    dynamic api,
    Object? section,
  ) {
    if (section is! Map<String, dynamic>) return const [];
    final rawResults = section['results'];
    if (rawResults is! List) return const [];
    final items = rawResults
        .whereType<Map<String, dynamic>>()
        .map(SeerrDiscoverItem.fromJson)
        .toList(growable: false);
    return api.postersFromDiscoverResults(items);
  }

  /// OX recently-added uses discover-shaped rows; parse without SeerrMedia chopper DTO.
  static Future<List<SeerrDashboardPosterModel>?> fetchRecentlyAddedPosters(Ref ref) async {
    final creds = ref.read(userProvider)?.seerrCredentials;
    final base = creds?.serverUrl.trim();
    if (!OxplayerEnv.isEnabled || base == null || base.isEmpty || creds?.useProxy != true) {
      return null;
    }

    final uri = Uri.parse('$base/api/v1/media').replace(
      queryParameters: {
        'filter': 'allavailable',
        'sort': 'mediaAdded',
        'take': '10',
        'skip': '0',
      },
    );
    final headers = oxCatalogApiHeaders(ref);

    http.Response response;
    try {
      response = await http.get(uri, headers: headers);
    } catch (_) {
      return null;
    }
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return null;
    final api = ref.read(seerrApiProvider);
    return _posters(api, body);
  }
}
