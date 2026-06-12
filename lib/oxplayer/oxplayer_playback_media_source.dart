import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Resolves the playable [MediaSourceInfo] from a PlaybackInfo response.
///
/// OX PlaybackInfo returns exactly one fully populated source (the resolved
/// variant). Catalog may list multiple variants at higher indices — do not
/// index by [versionStreamIndex] here.
MediaSourceInfo? oxplayerResolvePlaybackMediaSource(
  PlaybackInfoResponse? playbackInfo,
) {
  final sources = playbackInfo?.mediaSources;
  if (sources == null || sources.isEmpty) {
    return null;
  }
  return sources.firstWhere(
    (s) => (s.path ?? '').isNotEmpty || (s.id ?? '').isNotEmpty,
    orElse: () => sources.first,
  );
}
