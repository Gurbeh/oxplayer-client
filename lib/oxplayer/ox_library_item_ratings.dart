import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// Cached Seerr ratings for a library item detail page (keyed by catalog item id).
final oxLibraryItemRatingsProvider = StateProvider.family<SeerrRatingsResponse?, String>((ref, itemId) => null);

/// Reads `OxRatings` from a Jellyfin item JSON payload.
SeerrRatingsResponse? oxRatingsFromItemJson(Map<String, dynamic> raw) {
  return oxParseSeerrRatingsJson(raw['OxRatings']);
}

void oxApplyLibraryItemRatings(Ref ref, String itemId, SeerrRatingsResponse? ratings) {
  if (!OxplayerEnv.isEnabled) return;
  ref.read(oxLibraryItemRatingsProvider(itemId).notifier).state = ratings;
}

/// Fetches `GET /Items/{id}` and returns the raw JSON (includes `OxRatings` when present).
Future<Map<String, dynamic>?> oxFetchLibraryItemJson(Ref ref, String itemId) async {
  if (!OxplayerEnv.isEnabled) return null;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (baseUrl == null || baseUrl.isEmpty || token.isEmpty || itemId.isEmpty) {
    return null;
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: userId != null ? {'userId': userId} : null,
  );

  try {
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'MediaBrowser Token="$token"',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    return body is Map<String, dynamic> ? body : null;
  } catch (_) {
    return null;
  }
}

/// OX library detail fetch: one round-trip for item model + OxRatings.
Future<({ItemBaseModel model, SeerrRatingsResponse? ratings})?> oxFetchLibraryItemDetails(
  Ref ref,
  String itemId,
) async {
  final raw = await oxFetchLibraryItemJson(ref, itemId);
  if (raw == null) return null;

  final dto = BaseItemDto.fromJsonFactory(raw);
  final model = ItemBaseModel.fromBaseDto(dto, ref);
  final ratings = oxRatingsFromItemJson(raw);
  oxApplyLibraryItemRatings(ref, itemId, ratings);
  return (model: model, ratings: ratings);
}

/// Rotten Tomatoes / IMDb badges for library detail headers (matches SeerrDetailsScreen).
List<SimpleLabel> oxSeerrRatingLabels(BuildContext context, SeerrRatingsResponse? ratings) {
  if (ratings == null) return const [];

  final labels = <SimpleLabel>[];
  final rt = ratings.rt;

  if (rt?.criticsScore != null) {
    labels.add(
      SimpleLabel(
        label: Text('${rt!.criticsScore}%'),
        iconWidget: SvgPicture.asset(
          'icons/tomato.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        iconColor: Colors.white,
        color: Colors.redAccent.shade700,
      ),
    );
    if (rt.audienceScore != null) {
      labels.add(
        SimpleLabel(
          label: Text('${rt.audienceScore}%'),
          iconWidget: SvgPicture.asset(
            'icons/popcorn_bucket.svg',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          iconColor: Colors.white,
          color: Colors.orange.shade700,
        ),
      );
    }
  }

  final imdbScore = ratings.imdb?.criticsScore;
  if (imdbScore != null) {
    labels.add(
      SimpleLabel(
        label: Text(imdbScore.toStringAsFixed(1)),
        icon: Icons.star_rounded,
        iconColor: Colors.black,
        color: Colors.amber.shade600,
      ),
    );
  }

  return labels;
}
