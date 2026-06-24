import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_catalog_poster.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// TMDB recommendations for a catalog item via OX Jellyfin shim (`GET /Items/{id}/Recommendations`).
Future<List<SeerrDashboardPosterModel>> oxFetchItemRecommendations(
  Ref ref,
  String itemId, {
  int limit = 24,
}) async {
  final baseUrl = ref.read(serverUrlProvider);
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (baseUrl == null || baseUrl.isEmpty || token.isEmpty) {
    return const [];
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId/Recommendations').replace(
    queryParameters: {'Limit': '$limit'},
  );

  try {
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'MediaBrowser Token="$token"',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return const [];

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return const [];
    final items = body['Items'];
    if (items is! List) return const [];

    final posters = <SeerrDashboardPosterModel>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final dto = BaseItemDto.fromJsonFactory(raw);
      final poster = oxplayerPosterFromCatalogDto(dto, ref);
      if (poster != null) posters.add(poster);
    }
    return posters;
  } catch (_) {
    return const [];
  }
}
