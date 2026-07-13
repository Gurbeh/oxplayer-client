import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';

/// Series detail episode focus — separate from [SeriesModel.selectedEpisode] because
/// dart_mappable copyWith compares optional fields with `==`, and [EpisodeModel]'s
/// equality operator rejects non-[ItemBaseModel] sentinels.
final oxSeriesSelectedEpisodeIdProvider =
    StateProvider.autoDispose.family<String?, String>((ref, seriesId) => null);

void oxSetSeriesSelectedEpisode(WidgetRef ref, String seriesId, EpisodeModel? episode) {
  ref.read(oxSeriesSelectedEpisodeIdProvider(seriesId).notifier).state = episode?.id;
}

EpisodeModel? oxSeriesSelectedEpisode(WidgetRef ref, SeriesModel? series) {
  if (series == null) return null;
  final id = ref.watch(oxSeriesSelectedEpisodeIdProvider(series.id));
  if (id == null) return null;
  return series.availableEpisodes?.firstWhereOrNull((episode) => episode.id == id);
}
