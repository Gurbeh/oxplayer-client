import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/oxplayer_home_refresh.dart';
import 'package:fladder/oxplayer/oxplayer_playback_user_data_derive.dart';
import 'package:fladder/providers/items/episode_details_provider.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/items/series_details_provider.dart';

export 'package:fladder/oxplayer/oxplayer_playback_user_data_derive.dart';

/// Patch in-memory detail providers with stop position — no network.
void oxPatchDetailProvidersPlaybackProgress(
  WidgetRef ref, {
  required ItemBaseModel item,
  required Duration position,
  required Duration runTime,
}) {
  final effectiveRunTime = runTime > Duration.zero
      ? runTime
      : (item.overview.runTime ?? Duration.zero);
  final nextUserData = oxDerivePlaybackUserData(
    current: item.userData,
    position: position,
    runTime: effectiveRunTime,
  );

  switch (item) {
    case MovieModel movie:
      final movieProv = movieDetailsProvider(movie.id);
      final snap = ref.read(movieProv);
      if (snap != null) {
        ref.read(movieProv.notifier).patchUserData(nextUserData);
      }
      return;
    case EpisodeModel episode:
      final epProv = episodeDetailsProvider(episode.id);
      final epSnap = ref.read(epProv);
      final currentEp = epSnap.episode;
      if (currentEp != null && currentEp.id == episode.id) {
        ref.read(epProv.notifier).updateEpisode(
              currentEp.copyWith(userData: nextUserData),
            );
      }
      final seriesId = episode.parentId;
      if (seriesId == null || seriesId.isEmpty) return;
      final seriesProv = seriesDetailsProvider(seriesId);
      final seriesSnap = ref.read(seriesProv);
      if (seriesSnap == null) return;
      final patched = episode.copyWith(userData: nextUserData);
      ref.read(seriesProv.notifier).updateEpisodeInfo(patched);
      if (seriesSnap.selectedEpisode?.id == episode.id) {
        ref.read(seriesProv.notifier).setCurrentEpisode(patched);
      }
      return;
    default:
      return;
  }
}

/// Soft-refresh home shelves after playback (Continue Watching / Next Up).
Future<void> oxRefreshHomeAfterPlayback(WidgetRef ref) async {
  try {
    await OxplayerHomeRefresh.refresh(ref);
  } catch (_) {}
}
