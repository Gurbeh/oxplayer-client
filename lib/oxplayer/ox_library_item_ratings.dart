import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_api_disk_cache.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_user_data_derive.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
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

/// Loads Seerr TV RT scores in the background (does not block series detail load).
void oxPrefetchSeerrTvRatings(Ref ref, String itemId, int? tmdbId) {
  if (!OxplayerEnv.isEnabled || tmdbId == null || tmdbId <= 0) return;
  if (ref.read(userProvider)?.seerrCredentials?.isConfigured != true) return;
  unawaited(() async {
    try {
      final rt = await ref.read(seerrApiProvider).tvRatings(tmdbId);
      final merged = oxMergeSeerrRatings(
        rt != null ? SeerrRatingsResponse(rt: rt) : null,
        ref.read(oxLibraryItemRatingsProvider(itemId)),
      );
      oxApplyLibraryItemRatings(ref, itemId, merged);
    } catch (_) {}
  }());
}

/// Fetches `GET /Items/{id}` and returns the raw JSON (includes `OxRatings` when present).
/// Writes disk SWR cache on 200 so the next open can hydrate Play instantly.
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
    if (body is! Map<String, dynamic>) return null;

    final cacheUserId = userId ?? '';
    if (cacheUserId.isNotEmpty && response.body.isNotEmpty) {
      await OxplayerApiDiskCache.write(
        OxplayerApiDiskCache.key(userId: cacheUserId, method: 'GET', uri: uri),
        OxplayerApiDiskCacheEntry(
          savedAt: DateTime.now().toUtc(),
          statusCode: response.statusCode,
          body: response.body,
          headers: {'content-type': response.headers['content-type'] ?? 'application/json'},
        ),
      );
    }

    return body;
  } catch (_) {
    return null;
  }
}

/// Fresh `GET /Items/{id}` for playback resume — never reads disk SWR first.
///
/// SWR can return stale [UserData.playbackPositionTicks]; resume must use server truth.
Future<ItemBaseModel?> oxFetchFreshItemForPlayback(Ref ref, String itemId) async {
  if (!OxplayerEnv.isEnabled || itemId.isEmpty) return null;
  final raw = await oxFetchLibraryItemJson(ref, itemId);
  if (raw == null) return null;
  try {
    final dto = BaseItemDto.fromJsonFactory(raw);
    return ItemBaseModel.fromBaseDto(dto, ref);
  } catch (_) {
    return null;
  }
}

/// After playback stop/progress, patch disk SWR so detail resume label matches server.
Future<void> oxPatchLibraryItemPlaybackInCache(
  Ref ref,
  String itemId,
  Duration position,
) async {
  if (!OxplayerEnv.isEnabled || itemId.isEmpty) return;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  if (baseUrl == null || baseUrl.isEmpty || userId == null || userId.isEmpty) return;

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: {'userId': userId},
  );
  final cacheKey = OxplayerApiDiskCache.key(userId: userId, method: 'GET', uri: uri);
  final entry = await OxplayerApiDiskCache.read(cacheKey);
  if (entry == null || entry.body.isEmpty) return;

  try {
    final decoded = jsonDecode(entry.body);
    if (decoded is! Map<String, dynamic>) return;

    final runTimeTicks = decoded['RunTimeTicks'];
    final runTime = runTimeTicks is num && runTimeTicks > 0
        ? Duration(milliseconds: (runTimeTicks / 10000).round())
        : Duration.zero;
    final existing = decoded['UserData'];
    final current = existing is Map<String, dynamic>
        ? UserData(
            isFavourite: existing['IsFavorite'] == true,
            playCount: existing['PlayCount'] is num ? (existing['PlayCount'] as num).toInt() : 0,
            playbackPositionTicks:
                existing['PlaybackPositionTicks'] is num ? (existing['PlaybackPositionTicks'] as num).toInt() : 0,
            progress: existing['PlayedPercentage'] is num ? (existing['PlayedPercentage'] as num).toDouble() : 0,
            played: existing['Played'] == true,
          )
        : const UserData();
    final next = oxDerivePlaybackUserData(
      current: current,
      position: position,
      runTime: runTime,
    );
    decoded['UserData'] = {
      if (existing is Map<String, dynamic>) ...existing,
      'PlaybackPositionTicks': next.playbackPositionTicks,
      'PlayedPercentage': next.progress,
      'Played': next.played,
      'PlayCount': next.playCount,
      if (next.lastPlayed != null) 'LastPlayedDate': next.lastPlayed!.toUtc().toIso8601String(),
    };

    await OxplayerApiDiskCache.write(
      cacheKey,
      OxplayerApiDiskCacheEntry(
        savedAt: DateTime.now().toUtc(),
        statusCode: entry.statusCode,
        body: jsonEncode(decoded),
        headers: entry.headers,
      ),
    );
  } catch (_) {}
}

/// Disk SWR: last successful `GET /Items/{id}` body (survives kill / dispose).
Future<Map<String, dynamic>?> oxLoadCachedLibraryItemJson(Ref ref, String itemId) async {
  if (!OxplayerEnv.isEnabled || itemId.isEmpty) return null;

  final baseUrl = ref.read(serverUrlProvider);
  final userId = ref.read(userProvider)?.id;
  if (baseUrl == null || baseUrl.isEmpty || userId == null || userId.isEmpty) {
    return null;
  }

  final uri = Uri.parse('$baseUrl/Items/$itemId').replace(
    queryParameters: {'userId': userId},
  );
  final entry = await OxplayerApiDiskCache.read(
    OxplayerApiDiskCache.key(userId: userId, method: 'GET', uri: uri),
  );
  if (entry == null || entry.body.isEmpty) return null;
  try {
    final body = jsonDecode(entry.body);
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

/// Hydrate detail model from disk without waiting on network (Play / MediaSources).
Future<({ItemBaseModel model, SeerrRatingsResponse? ratings})?> oxLoadCachedLibraryItemDetails(
  Ref ref,
  String itemId,
) async {
  final raw = await oxLoadCachedLibraryItemJson(ref, itemId);
  if (raw == null) return null;

  try {
    final dto = BaseItemDto.fromJsonFactory(raw);
    final model = ItemBaseModel.fromBaseDto(dto, ref);
    final ratings = oxRatingsFromItemJson(raw);
    oxApplyLibraryItemRatings(ref, itemId, ratings);
    return (model: model, ratings: ratings);
  } catch (_) {
    return null;
  }
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
