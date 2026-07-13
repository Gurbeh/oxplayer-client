import 'package:collection/collection.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';

/// Resolves a playable audio stream when Jellyfin default index is wrong (e.g. 0 = video).
AudioStreamModel? oxplayerResolvePlaybackAudioStream(PlaybackModel model) {
  final streams = model.audioStreams;
  if (streams == null || streams.isEmpty) return null;

  final wantIdx = model.mediaStreams?.defaultAudioStreamIndex;
  final matched = streams.firstWhereOrNull((s) => s.index == wantIdx);
  if (matched != null && matched.index != AudioStreamModel.no().index) {
    return matched;
  }

  return streams.firstWhereOrNull((s) => s.index >= 0);
}
