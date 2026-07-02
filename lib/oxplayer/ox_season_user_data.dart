import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';

/// Fladder treats seasons with zero playable-unwatched episodes as fully watched (check icon).
/// Virtual/missing TMDB episodes are not playable — count them so the season is not marked watched.
UserData oxSeasonUserDataFromEpisodes(Iterable<EpisodeModel> seasonEpisodes) {
  final unplayedAvailable = seasonEpisodes
      .where((episode) => episode.status == EpisodeStatus.available && !episode.userData.played)
      .length;
  if (unplayedAvailable > 0) {
    return UserData(unPlayedItemCount: unplayedAvailable, played: false);
  }

  final unavailable = seasonEpisodes.where((episode) => episode.status != EpisodeStatus.available).length;
  if (unavailable > 0) {
    return UserData(unPlayedItemCount: unavailable, played: false);
  }

  return const UserData(unPlayedItemCount: 0, played: true);
}
