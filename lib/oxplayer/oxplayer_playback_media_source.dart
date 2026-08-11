import 'package:collection/collection.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

bool oxplayerMediaSourceHasPlayableUrl(MediaSourceInfo source) {
  final path = (source.path ?? '').trim();
  if (path.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(path);
  return uri != null && uri.hasScheme && uri.hasAuthority;
}

/// Resolves the playable [MediaSourceInfo] from a PlaybackInfo response.
///
/// OX aligns [PlaybackInfoResponse.mediaSources] indices with catalog variants;
/// only the resolved row carries a playable URL (a Telegram t.me link) — other slots are id-only stubs.
MediaSourceInfo? oxplayerResolvePlaybackMediaSource(
  PlaybackInfoResponse? playbackInfo, {
  String? requestedMediaSourceId,
}) {
  final sources = playbackInfo?.mediaSources;
  if (sources == null || sources.isEmpty) {
    return null;
  }

  final requested = requestedMediaSourceId?.trim();
  if (requested != null && requested.isNotEmpty) {
    final match = sources.firstWhereOrNull(
      (s) => s.id == requested && oxplayerMediaSourceHasPlayableUrl(s),
    );
    if (match != null) {
      return match;
    }
  }

  return sources.firstWhereOrNull(oxplayerMediaSourceHasPlayableUrl) ?? sources.first;
}
