import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';

/// Whether the detail page should show stream pickers (version / audio / sub).
///
/// Fladder gates on [MediaStreamsModel.isNotEmpty] (audio + subs required).
/// OX items may have multiple file variants before probe completes — still show
/// the version picker when more than one [MediaSource] exists.
bool oxplayerShowMediaStreamHelper(MediaStreamsModel streams) {
  return streams.versionStreams.length > 1 || streams.isNotEmpty;
}

/// Browse-only or catalog movies without attached files have no version streams.
bool oxMovieHasPlayableMedia(MovieModel movie) {
  return movie.mediaStreams.versionStreams.isNotEmpty;
}

/// Label for a version/file option in the play-button picker.
String oxplayerVersionStreamLabel(VersionStreamModel stream) {
  if (stream.name.trim().isNotEmpty) {
    return stream.name.trim();
  }
  final resolution = stream.detailedResolutionLabel.trim();
  if (resolution.isNotEmpty && resolution != 'Unknown Unknown') {
    return resolution;
  }
  final id = stream.id?.trim();
  if (id != null && id.isNotEmpty) {
    return id.replaceFirst(RegExp(r'^ms_'), 'Variant ');
  }
  return 'Variant ${stream.index + 1}';
}
