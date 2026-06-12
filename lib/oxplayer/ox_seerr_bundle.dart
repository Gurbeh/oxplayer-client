import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

const _tmdbImageBase = 'https://image.tmdb.org/t/p/w500';

/// Fetches `GET /tmdb/seerr-bundle` from oxplayer-be (VIP+ TMDB fallback).
Future<Map<String, dynamic>?> oxFetchSeerrBundle(
  Ref ref, {
  required int tmdbId,
  required String mediaType,
}) async {
  final base = OxplayerEnv.apiBaseUrl;
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (base == null || token.isEmpty) return null;

  final uri = Uri.parse('$base/tmdb/seerr-bundle').replace(
    queryParameters: {
      'tmdbId': '$tmdbId',
      'mediaType': mediaType,
    },
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

List<SeerrDashboardPosterModel> oxPosterCardsFromBundle(
  dynamic raw,
  String defaultMediaType,
) {
  if (raw is! List) return const [];
  final posters = <SeerrDashboardPosterModel>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;
    final poster = _posterFromBundleCard(entry, defaultMediaType);
    if (poster != null) posters.add(poster);
  }
  return posters;
}

SeerrDashboardPosterModel? _posterFromBundleCard(
  Map<String, dynamic> card,
  String defaultMediaType,
) {
  final tmdbId = card['tmdbId'];
  final id = tmdbId is int ? tmdbId : int.tryParse('$tmdbId') ?? 0;
  if (id <= 0) return null;

  final mediaType = (card['mediaType'] as String?) ?? defaultMediaType;
  final type = mediaType == 'tv' ? SeerrMediaType.tvshow : SeerrMediaType.movie;
  final posterPath = card['posterPath'] as String?;
  final posterUrl = posterPath != null && posterPath.isNotEmpty ? '$_tmdbImageBase$posterPath' : null;

  ImageData? primary;
  if (posterUrl != null) {
    primary = ImageData(path: posterUrl, key: 'ox_bundle_$id');
  }

  SeerrMediaInfo? mediaInfo;
  if (card['mediaInfo'] is Map<String, dynamic>) {
    mediaInfo = SeerrMediaInfo.fromJson(card['mediaInfo'] as Map<String, dynamic>);
  }

  return SeerrDashboardPosterModel(
    id: '$id',
    type: type,
    tmdbId: id,
    jellyfinItemId: mediaInfo?.primaryJellyfinMediaId,
    title: (card['title'] as String?) ?? '',
    overview: (card['overview'] as String?) ?? '',
    images: ImagesData(primary: primary),
    mediaStatus: mediaInfo?.mediaStatus ?? SeerrMediaStatus.unknown,
    mediaInfo: mediaInfo,
    releaseYear: card['year'] as String?,
  );
}
