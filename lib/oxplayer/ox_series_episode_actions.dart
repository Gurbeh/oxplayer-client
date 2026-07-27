import 'package:collection/collection.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Series with no watched or in-progress episode — user must pick season + episode first.
bool oxSeriesNeedsEpisodePick(SeriesModel? series) {
  if (series == null || !OxplayerConfig.isEnabled) return false;
  final episodes = series.availableEpisodes;
  if (episodes == null || episodes.isEmpty) return false;
  return !episodes.any((episode) => episode.userData.played || episode.userData.progress != 0);
}

class OxSeriesPickerSeason {
  const OxSeriesPickerSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodes,
  });

  final int seasonNumber;
  final String name;
  final List<EpisodeModel> episodes;
}

List<OxSeriesPickerSeason> oxSeriesPickerSeasons(SeriesModel series) {
  final episodes = series.availableEpisodes?.where((episode) => episode.season > 0).toList() ?? [];
  if (episodes.isEmpty) return const [];

  final bySeason = episodes.episodesBySeason;
  return bySeason.entries.map((entry) {
    final seasonMeta = series.seasons?.firstWhereOrNull((season) => season.season == entry.key);
    final name = _oxPickerSeasonName(seasonMeta, entry.key);
    return OxSeriesPickerSeason(
      seasonNumber: entry.key,
      name: name,
      episodes: entry.value,
    );
  }).toList();
}

String _oxPickerSeasonName(SeasonModel? seasonMeta, int seasonNumber) {
  if (seasonMeta != null) {
    if (seasonMeta.seasonName.isNotEmpty) return seasonMeta.seasonName;
    if (seasonMeta.name.isNotEmpty) return seasonMeta.name;
  }
  return seasonNumber.toString();
}

/// Play button / stream helper target on series detail — focused episode wins over Next Up.
EpisodeModel? oxSeriesDetailPlayTarget(
  SeriesModel? series, {
  EpisodeModel? selectedEpisode,
}) {
  if (series == null) return null;
  if (oxSeriesNeedsEpisodePick(series) && selectedEpisode == null) return null;
  return selectedEpisode ?? series.selectedEpisode ?? oxSeriesPlayableNextUp(series);
}
