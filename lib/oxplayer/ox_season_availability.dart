import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

int oxSeasonTotalEpisodeCount(SeasonModel season) {
  if (season.episodes.isNotEmpty) return season.episodes.length;
  if (season.episodeCount > 0) return season.episodeCount;
  return season.childCount ?? 0;
}

int oxSeasonAvailableEpisodeCount(SeasonModel season) {
  if (season.episodes.isEmpty) return 0;
  return season.episodes.where((episode) => episode.status == EpisodeStatus.available).length;
}

/// True when every on-disk episode in the season is marked played (Fladder check icon).
bool oxSeasonShowWatchedTick(SeasonModel season) {
  if (!OxplayerConfig.isEnabled) {
    return season.userData.unPlayedItemCount == 0;
  }
  if (season.episodes.isEmpty) {
    return season.userData.unPlayedItemCount == 0 && season.userData.played;
  }
  final available = season.episodes.where((episode) => episode.status == EpisodeStatus.available);
  if (available.isEmpty) return false;
  return available.every((episode) => episode.userData.played);
}

/// Season poster badge: `3/10` when partial, `0/10` when none on disk, `10` when complete.
String? oxSeasonPosterCountText(SeasonModel season) {
  if (!OxplayerConfig.isEnabled) return null;
  final total = oxSeasonTotalEpisodeCount(season);
  if (total <= 0) return null;
  final available = oxSeasonAvailableEpisodeCount(season);
  if (available < total) return '$available/$total';
  return total.toString();
}
