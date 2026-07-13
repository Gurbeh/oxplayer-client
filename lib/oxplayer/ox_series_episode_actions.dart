import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';

/// Play button / stream helper target on series detail — focused episode wins over Next Up.
EpisodeModel? oxSeriesDetailPlayTarget(
  SeriesModel? series, {
  EpisodeModel? selectedEpisode,
}) {
  if (series == null) return null;
  return selectedEpisode ?? series.selectedEpisode ?? oxSeriesPlayableNextUp(series);
}