import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/recommended_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_catalog_http.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/providers/user_provider.dart';

/// Library tab shelves from GET /Users/{id}/Views/{viewId}/Feed.
abstract final class OxplayerLibraryFeed {
  static const _feedLimit = 9;

  /// One HTTP round-trip for continue watching, next up, and latest.
  static Future<List<RecommendedModel>?> fetchShelves(Ref ref, ViewModel viewModel) async {
    final base = (OxplayerRoute.apiBaseUrl ?? OxplayerEnv.apiBaseUrl)?.trim();
    final userId = ref.read(userProvider)?.id;
    final viewId = viewModel.id;
    if (base == null || base.isEmpty || userId == null || userId.isEmpty || viewId.isEmpty) {
      return null;
    }

    final uri = Uri.parse('$base/Users/$userId/Views/$viewId/Feed').replace(
      queryParameters: {'limit': '$_feedLimit'},
    );
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

    final collectionType = viewModel.collectionType;
    final fetchContinue = collectionType == CollectionType.movies ||
        collectionType == CollectionType.tvshows ||
        collectionType == CollectionType.homevideos;
    final fetchNextUp = collectionType == CollectionType.tvshows;
    final fetchLatest = collectionType != CollectionType.livetv;

    final shelves = <RecommendedModel>[];

    if (fetchContinue) {
      final resume = _itemsFromSection(body['Resume'], ref);
      shelves.add(RecommendedModel(name: const Continue(), posters: resume, type: null));
    }

    if (fetchNextUp) {
      final nextUp = _itemsFromSection(body['NextUp'], ref);
      shelves.add(RecommendedModel(name: const NextUp(), posters: nextUp, type: null));
    }

    if (fetchLatest) {
      final latestRaw = body['Latest'];
      final latest = latestRaw is List
          ? latestRaw
              .whereType<Map<String, dynamic>>()
              .map((item) => ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(item), ref))
              .toList()
          : const <ItemBaseModel>[];
      shelves.add(RecommendedModel(name: const Latest(), posters: latest, type: null));
    }

    return shelves..removeWhere((element) => element.posters.isEmpty);
  }

  static List<ItemBaseModel> _itemsFromSection(Object? section, Ref ref) {
    if (section is! Map<String, dynamic>) return const [];
    final rawItems = section['Items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(item), ref))
        .toList();
  }
}
