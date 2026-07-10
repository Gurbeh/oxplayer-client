import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

int oxSeasonTotalEpisodeCount(SeasonModel season) {
  if (season.episodeCount > 0) return season.episodeCount;
  if (season.episodes.isNotEmpty) return season.episodes.length;
  return season.childCount ?? 0;
}

int oxSeasonAvailableEpisodeCount(SeasonModel season) {
  if (season.episodes.isNotEmpty) {
    final fromEpisodes = season.episodes
        .where((episode) => episode.status == EpisodeStatus.available)
        .length;
    if (fromEpisodes > 0) return fromEpisodes;
  }
  return season.childCount ?? 0;
}

/// True when every on-disk episode in the season is marked played (Fladder check icon).
bool oxSeasonShowWatchedTick(SeasonModel season) {
  if (!OxplayerConfig.isEnabled) {
    return season.userData.unPlayedItemCount == 0;
  }
  final total = oxSeasonTotalEpisodeCount(season);
  final onDisk = oxSeasonAvailableEpisodeCount(season);
  if (season.episodes.isEmpty) {
    if (onDisk < total) return false;
    return (season.userData.unPlayedItemCount ?? 0) == 0;
  }
  final playable = season.episodes.where((episode) => episode.status == EpisodeStatus.available);
  if (playable.isEmpty) return false;
  return playable.every((episode) => episode.userData.played);
}

/// Season poster badge: `3/10` partial on disk, `0/10` none, unplayed when full on disk, else tick.
String? oxSeasonPosterCountText(SeasonModel season) {
  if (!OxplayerConfig.isEnabled) return null;
  final total = oxSeasonTotalEpisodeCount(season);
  if (total <= 0) return null;
  final onDisk = oxSeasonAvailableEpisodeCount(season);
  if (onDisk < total) return '$onDisk/$total';
  final unplayed = season.userData.unPlayedItemCount;
  if (unplayed != null && unplayed > 0) return unplayed.toString();
  return null;
}
