import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Fladder uses blurOnly for unavailable episodes, which hides real images; OX supplies still art.
ImageData? oxEpisodePosterImage(EpisodeModel episode, bool episodeAvailable) {
  if (!OxplayerConfig.isEnabled || episodeAvailable) return null;
  return episode.images?.primary ?? episode.parentImages?.primary;
}
