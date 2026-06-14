import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// TMDB "Specials" — OX never surfaces or requests season 0.
bool oxIsRequestableSeasonNumber(int? seasonNumber) {
  return seasonNumber != null && seasonNumber > 0;
}

bool oxSeasonIsFullyAvailable(SeerrMediaStatus? status) {
  return status == SeerrMediaStatus.available;
}

Iterable<SeerrSeason> oxRequestableSeasons(List<SeerrSeason> seasons) {
  return seasons.where((s) => oxIsRequestableSeasonNumber(s.seasonNumber));
}

/// True when at least one non-special season is not fully [SeerrMediaStatus.available].
bool oxHasRequestableSeasons({
  required List<SeerrSeason> seasons,
  required Map<int, SeerrMediaStatus> seasonStatuses,
}) {
  final seasonNumbers = <int>{
    ...oxRequestableSeasons(seasons).map((s) => s.seasonNumber!),
    ...seasonStatuses.keys.where(oxIsRequestableSeasonNumber),
  };
  if (seasonNumbers.isEmpty) return false;

  for (final number in seasonNumbers) {
    if (!oxSeasonIsFullyAvailable(seasonStatuses[number])) {
      return true;
    }
  }
  return false;
}

bool oxShouldShowSeriesRequestButton({
  required String? seerrUrl,
  required int? tmdbId,
  required bool seerrConfigured,
  required List<SeerrSeason> seasons,
  required Map<int, SeerrMediaStatus> seasonStatuses,
}) {
  if (seerrUrl == null || seerrUrl.isEmpty) return false;
  if (tmdbId == null) return false;
  if (!seerrConfigured) return false;
  return oxHasRequestableSeasons(seasons: seasons, seasonStatuses: seasonStatuses);
}
