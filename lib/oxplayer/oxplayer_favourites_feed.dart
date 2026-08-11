import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_catalog_http.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

/// Parsed favorites tab from GET /Users/{id}/Favorites/Feed.
class OxFavoritesFeedResult {
  const OxFavoritesFeedResult({
    required this.favourites,
    required this.people,
  });

  final Map<FladderItemType, List<ItemBaseModel>> favourites;
  final List<ItemBaseModel> people;
}

abstract final class OxplayerFavoritesFeed {
  static const _limitPerType = 15;

  /// One HTTP round-trip for all favorited items and people.
  static Future<OxFavoritesFeedResult?> fetch(Ref ref) async {
    if (!OxplayerConfig.isEnabled) return null;

    final base = OxplayerEnv.apiBaseUrl?.trim();
    final userId = ref.read(userProvider)?.id;
    if (base == null || base.isEmpty || userId == null || userId.isEmpty) {
      return null;
    }

    final uri = Uri.parse('$base/Users/$userId/Favorites/Feed').replace(
      queryParameters: {'limit': '$_limitPerType'},
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

    final rawItems = body['Items'];
    final items = <ItemBaseModel>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        items.add(ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(raw), ref));
      }
    }

    final rawPeople = body['People'];
    final people = <ItemBaseModel>[];
    if (rawPeople is List) {
      for (final raw in rawPeople) {
        if (raw is! Map<String, dynamic>) continue;
        people.add(ItemBaseModel.fromBaseDto(BaseItemDto.fromJson(raw), ref));
      }
    }

    return OxFavoritesFeedResult(
      favourites: items.groupedItems,
      people: people,
    );
  }
}
