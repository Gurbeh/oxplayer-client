import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/items/episode_details_provider.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/items/season_details_provider.dart';
import 'package:fladder/providers/items/series_details_provider.dart';

/// Refetches detail notifiers after Jellyfin watch/unwatch calls.
///
/// [RefreshContextExtension.refreshData] often finds no [RefreshState] when the action
/// runs from a modal bottom sheet (`useRootNavigator`), so pull-to-refresh never fires.
Future<void> refreshAfterWatchStateChange(WidgetRef ref, ItemBaseModel item) async {
  switch (item) {
    case MovieModel m:
      final movieProv = movieDetailsProvider(m.id);
      if (ref.read(movieProv) != null) {
        await ref.read(movieProv.notifier).fetchDetails(m);
      }
      return;
    case SeasonModel s:
      final seasonProv = seasonDetailsProvider(s.id);
      if (ref.read(seasonProv) != null) {
        await ref.read(seasonProv.notifier).fetchDetails(s.id);
      }
      final seriesId = s.seriesId;
      if (seriesId.isEmpty) return;
      final seriesProv = seriesDetailsProvider(seriesId);
      final seriesSnap = ref.read(seriesProv);
      if (seriesSnap != null) {
        await ref.read(seriesProv.notifier).fetchDetails(seriesSnap);
      }
      return;
    case SeriesModel s:
      final seriesProv = seriesDetailsProvider(s.id);
      final seriesSnap = ref.read(seriesProv);
      if (seriesSnap != null) {
        await ref.read(seriesProv.notifier).fetchDetails(seriesSnap);
      }
      return;
    case EpisodeModel e:
      final epProv = episodeDetailsProvider(e.id);
      if (ref.read(epProv).episode != null) {
        await ref.read(epProv.notifier).fetchDetails(e);
      }
      final seriesId = e.parentId;
      if (seriesId == null || seriesId.isEmpty) return;
      final seriesProv = seriesDetailsProvider(seriesId);
      final seriesSnap = ref.read(seriesProv);
      if (seriesSnap != null) {
        await ref.read(seriesProv.notifier).fetchDetails(seriesSnap);
      }
      return;
    default:
      return;
  }
}
