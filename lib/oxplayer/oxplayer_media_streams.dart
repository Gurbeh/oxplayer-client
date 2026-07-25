import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_variant_label.dart';

export 'package:fladder/oxplayer/oxplayer_variant_label.dart' show oxplayerVersionStreamLabel;

/// Whether the detail page should show stream pickers (version / audio / sub).
///
/// Fladder gates on [MediaStreamsModel.isNotEmpty] (audio + subs required).
/// OX items may have multiple file variants before probe completes — still show
/// the version picker when more than one [MediaSource] exists.
bool oxplayerShowMediaStreamHelper(MediaStreamsModel streams) {
  if (OxplayerConfig.isEnabled) {
    return streams.versionStreams.isNotEmpty;
  }
  return streams.versionStreams.length > 1 || streams.isNotEmpty;
}

/// Whether the file/version picker should appear in the detail header.
///
/// OX always shows the current file label when at least one variant exists,
/// even when there is only one playable option.
bool oxplayerShowVersionStreamPicker(MediaStreamsModel streams) {
  if (OxplayerConfig.isEnabled) {
    return streams.versionStreams.isNotEmpty;
  }
  return streams.versionStreams.length > 1;
}

/// Browse-only or catalog movies without attached files have no version streams.
bool oxMovieHasPlayableMedia(MovieModel movie) {
  return movie.mediaStreams.versionStreams.isNotEmpty;
}
