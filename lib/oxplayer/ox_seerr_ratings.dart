import 'package:fladder/seerr/seerr_models.dart';

int? oxIntFromJson(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double? oxDoubleFromJson(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

SeerrRtRating? oxParseSeerrRtJson(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;

  final criticsScore = oxIntFromJson(raw['criticsScore']);
  final audienceScore = oxIntFromJson(raw['audienceScore']);
  final title = raw['title'] as String?;
  final url = raw['url'] as String?;
  final year = oxIntFromJson(raw['year']);
  final criticsRating = raw['criticsRating'] as String?;
  final audienceRating = raw['audienceRating'] as String?;

  if (criticsScore == null &&
      audienceScore == null &&
      title == null &&
      url == null &&
      year == null &&
      criticsRating == null &&
      audienceRating == null) {
    return null;
  }

  return SeerrRtRating(
    title: title,
    year: year,
    criticsScore: criticsScore,
    criticsRating: criticsRating,
    audienceScore: audienceScore,
    audienceRating: audienceRating,
    url: url,
  );
}

SeerrImdbRating? oxParseSeerrImdbJson(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;

  final criticsScore = oxDoubleFromJson(raw['criticsScore']);
  final title = raw['title'] as String?;
  final url = raw['url'] as String?;
  if (criticsScore == null && title == null && url == null) return null;

  return SeerrImdbRating(
    title: title,
    url: url,
    criticsScore: criticsScore,
  );
}

/// Parses Seerr-shaped ratings JSON (`{ rt?, imdb? }` or flat TV RT object).
SeerrRatingsResponse? oxParseSeerrRatingsJson(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;

  try {
    if (raw.containsKey('rt') || raw.containsKey('imdb')) {
      return SeerrRatingsResponse(
        rt: oxParseSeerrRtJson(raw['rt']),
        imdb: oxParseSeerrImdbJson(raw['imdb']),
      );
    }
    // TV `/ratings` returns a flat RT object.
    if (raw.containsKey('criticsScore') || raw.containsKey('audienceScore')) {
      final rt = oxParseSeerrRtJson(raw);
      return rt == null ? null : SeerrRatingsResponse(rt: rt);
    }
    return SeerrRatingsResponse.fromJson(raw);
  } catch (_) {
    return null;
  }
}

SeerrRtRating? oxMergeSeerrRt(SeerrRtRating? primary, SeerrRtRating? fallback) {
  if (primary == null) return fallback;
  if (fallback == null) return primary;

  return SeerrRtRating(
    title: primary.title ?? fallback.title,
    year: primary.year ?? fallback.year,
    criticsScore: primary.criticsScore ?? fallback.criticsScore,
    criticsRating: primary.criticsRating ?? fallback.criticsRating,
    audienceScore: primary.audienceScore ?? fallback.audienceScore,
    audienceRating: primary.audienceRating ?? fallback.audienceRating,
    url: primary.url ?? fallback.url,
  );
}

SeerrImdbRating? oxMergeSeerrImdb(SeerrImdbRating? primary, SeerrImdbRating? fallback) {
  if (primary == null) return fallback;
  if (fallback == null) return primary;

  return SeerrImdbRating(
    title: primary.title ?? fallback.title,
    url: primary.url ?? fallback.url,
    criticsScore: primary.criticsScore ?? fallback.criticsScore,
  );
}

/// Prefer non-null RT/IMDb fields from either source (bundle must not wipe Seerr API scores).
SeerrRatingsResponse? oxMergeSeerrRatings(
  SeerrRatingsResponse? primary,
  SeerrRatingsResponse? fallback,
) {
  if (primary == null) return fallback;
  if (fallback == null) return primary;

  return SeerrRatingsResponse(
    rt: oxMergeSeerrRt(primary.rt, fallback.rt),
    imdb: oxMergeSeerrImdb(primary.imdb, fallback.imdb),
  );
}

bool oxSeerrRatingsMissingRt(SeerrRatingsResponse? ratings) {
  return ratings?.rt?.criticsScore == null;
}
