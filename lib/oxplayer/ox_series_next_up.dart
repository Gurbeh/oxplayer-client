import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Fladder falls back to the first episode when none are playable; OX hides play instead.
EpisodeModel? oxSeriesPlayableNextUp(SeriesModel? series) {
  if (series == null) return null;
  if (!OxplayerConfig.isEnabled) return series.nextUp;
  return series.availableEpisodes?.nextUp;
}
