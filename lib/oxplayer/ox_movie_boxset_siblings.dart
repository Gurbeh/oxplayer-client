import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// Sibling movies from OX box sets (`GET /Items/{id}/BoxSets`).
Future<List<ItemBaseModel>> oxFetchMovieBoxSetSiblings(
  Ref ref,
  String itemId,
) async {
  final baseUrl = ref.read(serverUrlProvider);
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (baseUrl == null || baseUrl.isEmpty || token.isEmpty) {
    return const [];
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId/BoxSets');

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

    final posters = <ItemBaseModel>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final dto = BaseItemDto.fromJsonFactory(raw);
      posters.add(ItemBaseModel.fromBaseDto(dto, ref));
    }
    return posters;
  } catch (_) {
    return const [];
  }
}

final oxMovieBoxSetSiblingsProvider =
    FutureProvider.family<List<ItemBaseModel>, String>((ref, itemId) {
  return oxFetchMovieBoxSetSiblings(ref, itemId);
});
