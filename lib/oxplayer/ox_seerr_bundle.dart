import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_person_tmdb_id.dart';
import 'package:fladder/oxplayer/ox_seerr_images.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

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

/// Reads `logoUrl` (or `logoPath`) from a seerr-bundle poster object.
String? oxLogoUrlFromBundlePoster(Map<String, dynamic> poster) {
  final logoUrl = poster['logoUrl'] as String?;
  if (logoUrl != null && logoUrl.isNotEmpty) return logoUrl;

  final logoPath = poster['logoPath'] as String?;
  if (logoPath != null && logoPath.isNotEmpty) {
    return oxSeerrLogoUrl(logoPath);
  }
  return null;
}

ImagesData oxImagesWithBundleLogo(ImagesData images, String? logoUrl, {required String keyPrefix}) {
  if (logoUrl == null || logoUrl.isEmpty) return images;
  return ImagesData(
    primary: images.primary,
    backDrop: images.backDrop,
    logo: ImageData(path: logoUrl, key: '${keyPrefix}_logo'),
  );
}

/// Parses `ratings` from seerr-bundle into [SeerrRatingsResponse] (RT + IMDb).
SeerrRatingsResponse? oxRatingsFromBundle(Map<String, dynamic> bundle) {
  return oxParseSeerrRatingsJson(bundle['ratings']);
}

/// Merges bundle.poster.logoUrl into [poster] for SeerrDetailsScreen header art.
SeerrDashboardPosterModel oxMergeBundleLogoIntoPoster(
  SeerrDashboardPosterModel poster,
  Map<String, dynamic> bundle,
) {
  final posterMap = bundle['poster'];
  if (posterMap is! Map<String, dynamic>) return poster;

  final logoUrl = oxLogoUrlFromBundlePoster(posterMap);
  if (logoUrl == null) return poster;

  final keyPrefix = poster.type == SeerrMediaType.movie ? 'tmdb_movie_${poster.tmdbId}' : 'tmdb_tv_${poster.tmdbId}';
  return poster.copyWith(
    images: oxImagesWithBundleLogo(poster.images, logoUrl, keyPrefix: keyPrefix),
  );
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
  final posterUrl = oxSeerrPosterUrl(posterPath);

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

PersonKind? _personKindFromBundle(String? kind) {
  switch (kind?.toLowerCase().trim()) {
    case 'actor':
      return PersonKind.actor;
    case 'director':
      return PersonKind.director;
    case 'writer':
      return PersonKind.writer;
    case 'producer':
      return PersonKind.producer;
    case 'composer':
      return PersonKind.composer;
    default:
      return null;
  }
}

/// Parses cast/crew from `GET /tmdb/seerr-bundle` (always has TMDB person ids).
List<Person> oxPeopleFromBundle(Map<String, dynamic> bundle) {
  final raw = bundle['people'];
  if (raw is! List) return const [];

  final people = <Person>[];
  for (final entry in raw) {
    if (entry is! Map<String, dynamic>) continue;

    final tmdbId = oxTmdbPersonIdFromRawId('${entry['id'] ?? ''}');
    final name = (entry['name'] as String?)?.trim() ?? '';
    if (tmdbId == null || tmdbId <= 0 || name.isEmpty) continue;

    final role = (entry['role'] as String?)?.trim() ?? '';
    ImageData? image;
    final profilePath = entry['profilePath'];
    if (profilePath is String && profilePath.isNotEmpty) {
      final profileUrl = profilePath.startsWith('http') ? profilePath : oxSeerrProfileUrl(profilePath);
      if (profileUrl != null) {
        image = ImageData(path: profileUrl, key: 'ox_bundle_person_$tmdbId');
      }
    }

    people.add(
      Person(
        id: '$tmdbId',
        name: name,
        role: role,
        image: image,
        type: _personKindFromBundle(entry['kind'] as String?),
      ),
    );
  }
  return people;
}

/// Fills missing TMDB ids on Seerr credits using the OX TMDB bundle fallback.
List<Person> oxMergeSeerrPeople(List<Person> fromSeerr, Map<String, dynamic>? bundle) {
  final bundlePeople = bundle != null ? oxPeopleFromBundle(bundle) : const <Person>[];
  if (fromSeerr.isEmpty) return bundlePeople;
  if (bundlePeople.isEmpty) return fromSeerr;

  final bundleByName = {
    for (final person in bundlePeople) person.name.toLowerCase(): person,
  };

  return fromSeerr.map((person) {
    if (oxPersonHasNavigableTmdbId(person.id)) return person;

    final match = bundleByName[person.name.toLowerCase()];
    if (match == null) return person;

    return Person(
      id: match.id,
      name: person.name,
      image: person.image ?? match.image,
      role: person.role.isNotEmpty ? person.role : match.role,
      type: person.type ?? match.type,
    );
  }).toList();
}
