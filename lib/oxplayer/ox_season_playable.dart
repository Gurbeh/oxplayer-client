import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Virtual / TMDB-only seasons have no catalog row — hide Jellyfin user-data actions.
bool oxSeasonHasPlayableEpisodes(SeasonModel season) {
  if (!OxplayerConfig.isEnabled) return true;
  if (season.episodes.isEmpty) return false;
  return season.episodes.any((episode) => episode.status == EpisodeStatus.available);
}
