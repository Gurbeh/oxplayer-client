import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/offline_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/oxplayer_audio_log.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_audio.dart';
import 'package:fladder/oxplayer/oxplayer_memory_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/src/video_player_helper.g.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

bool nativeActivityStarted = false;

class NativePlayer extends BasePlayer implements VideoPlayerListenerCallback {
  final player = VideoPlayerApi();
  final activity = NativeVideoActivity();
  Timer? _playbackMemoryTimer;

  @override
  Future<void> dispose() async {
    _stopPlaybackMemoryWatch();
    nativeActivityStarted = false;
    return activity.disposeActivity();
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async => VideoPlayerListenerCallback.setUp(this);

  @override
  Future<void> loop(bool loop) {
    return player.setLooping(loop);
  }

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // Before VideoPlayerActivity launches, ExoPlayer is null — native open() queues
    // pendingOpenUrl and returns false. Retrying here only wastes time and spams Sentry.
    if (!nativeActivityStarted) {
      await player.open(url, play);
      return;
    }

    final maxAttempts = OxplayerConfig.isEnabled ? 6 : 4;
    final retryDelay = OxplayerConfig.isEnabled
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 350);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final ok = await player.open(url, play);
      if (ok) return;
      if (attempt < maxAttempts) {
        await Future<void>.delayed(retryDelay);
      } else {
        unawaited(OxplayerPlaybackTelemetry.reportNativeOpenFailed(
          url: url,
          attempt: attempt,
        ));
      }
    }
  }

  @override
  Future<StartResult> open(BuildContext newContext) async {
    OxplayerMemoryTelemetry.trimBeforeNativePlayback();
    nativeActivityStarted = true;
    _startPlaybackMemoryWatch();
    return activity.launchActivity();
  }

  void _startPlaybackMemoryWatch() {
    _playbackMemoryTimer?.cancel();
    if (!OxplayerConfig.isEnabled) return;
    _playbackMemoryTimer = Timer.periodic(
      kOxNativePlaybackMemorySampleInterval,
      (_) => unawaited(OxplayerMemoryTelemetry.sampleDuringNativePlayback()),
    );
  }

  void _stopPlaybackMemoryWatch() {
    _playbackMemoryTimer?.cancel();
    _playbackMemoryTimer = null;
  }

  @override
  Future<void> pause() {
    return player.pause();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> playOrPause() async {
    if (lastState.playing) {
      return player.pause();
    } else {
      return player.play();
    }
  }

  @override
  Future<void> seek(Duration position) {
    return player.seekTo(position.inMilliseconds);
  }

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    return model?.index ?? -1;
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    return model?.index ?? -1;
  }

  @override
  Future<void> setVolume(double volume) async {
    // Pigeon/ExoPlayer expect 0.0–1.0; settings store 0–100.
    final normalized = (volume / 100).clamp(0.0, 1.0);
    OxplayerAudioLog.event('native_set_volume', fields: {
      'backend': 'exo',
      'requested': volume,
      'exoVolume': normalized,
      'activityStarted': nativeActivityStarted,
    });
    return player.setVolume(normalized);
  }

  @override
  Future<void> stop() async {
    _stopPlaybackMemoryWatch();
    nativeActivityStarted = false;
    return player.stop();
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    return null;
  }

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey<State<StatefulWidget>>? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => null;

  @override
  void onPlaybackStateChanged(PlaybackState state) {
    final durationMs = state.duration;
    final duration = durationMs > 0 ? Duration(milliseconds: durationMs) : Duration.zero;
    lastState = lastState.update(
      playing: state.playing,
      position: Duration(milliseconds: state.position),
      buffer: Duration(milliseconds: state.buffered),
      buffering: state.buffering,
      completed: state.completed,
      duration: duration,
    );
    _stateController.add(lastState);
  }

  @override
  void onMuxedTracksDiscovered(
    List<NativeMuxedAudioRow> audio,
    List<NativeMuxedSubtitleRow> subtitles,
  ) {
    OxplayerAudioLog.event('native_muxed_tracks', fields: {
      'backend': 'exo',
      'exoAudioCount': audio.length,
      'exoSubCount': subtitles.length,
      'exoAudio': audio.map((t) => '${t.trackId}:${t.codec}').join(';'),
    });
    // Native ExoPlayer applies muxed tracks in onTracksChanged (properlySetSubAndAudioTracks).
    // Re-calling refreshDefaultTrackSelection here caused a select/deselect loop on TV Home resume.
  }

  @override
  void onPlaybackError(int errorCode, String errorCodeName, String? message) {
    unawaited(OxplayerPlaybackTelemetry.reportNativePlayerError(
      errorCode: errorCode,
      errorCodeName: errorCodeName,
      message: message,
    ));
  }

  final StreamController<PlayerState> _stateController = StreamController.broadcast();

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  Future<void> sendTVGuideModel(TVGuideModel guide) async {
    await player.sendTVGuideModel(guide);
  }

  Future<void> sendPlaybackDataToNative(
    BuildContext? context,
    PlaybackModel model,
    Duration startPosition,
  ) async {
    final playableData = PlayableData(
      currentItem: model.item.toSimpleItem(context),
      startPosition: startPosition.inMilliseconds,
      description: model.item.overview.summary,
      defaultAudioTrack: oxplayerResolvePlaybackAudioStream(model)?.index ??
          model.mediaStreams?.defaultAudioStreamIndex ??
          1,
      nextVideo: model.nextVideo?.toSimpleItem(context),
      previousVideo: model.previousVideo?.toSimpleItem(context),
      audioTracks: model.audioStreams
              ?.map(
                (audio) => AudioTrack(
                  name: audio.displayTitle,
                  languageCode: audio.language,
                  codec: audio.codec,
                  index: audio.index,
                  external: false,
                ),
              )
              .toList() ??
          [],
      defaultSubtrack: model.mediaStreams?.defaultSubStreamIndex ?? 1,
      subtitleTracks: model.subStreams
              ?.map(
                (sub) => SubtitleTrack(
                  name: sub.displayTitle,
                  languageCode: sub.language,
                  codec: sub.codec,
                  index: sub.index,
                  external: sub.isExternal,
                  url: sub.url,
                ),
              )
              .toList() ??
          [],
      segments: model.mediaSegments?.segments
              .map(
                (e) => MediaSegment(
                  type: MediaSegmentType.values.firstWhere((element) => element.name == e.type.name),
                  name: context != null ? e.type.label(context) : e.type.name,
                  start: e.start.inMilliseconds,
                  end: e.end.inMilliseconds,
                ),
              )
              .toList() ??
          [],
      trickPlayModel: model.trickPlay != null
          ? TrickPlayModel(
              width: model.trickPlay!.width,
              height: model.trickPlay!.height,
              tileWidth: model.trickPlay!.tileWidth,
              tileHeight: model.trickPlay!.tileHeight,
              thumbnailCount: model.trickPlay!.thumbnailCount,
              interval: model.trickPlay!.interval.inMilliseconds,
              images: model.trickPlay?.images ?? [])
          : null,
      chapters: model.chapters
              ?.map((e) => Chapter(name: e.name, url: e.imageUrl, time: e.startPosition.inMilliseconds))
              .toList() ??
          [],
      mediaInfo: MediaInfo(
        playbackType: switch (model) {
          DirectPlaybackModel() => PlaybackType.direct,
          OfflinePlaybackModel() => PlaybackType.offline,
          TranscodePlaybackModel() => PlaybackType.transcoded,
          TvPlaybackModel() => PlaybackType.tv,
          _ => PlaybackType.direct,
        },
        videoInformation: model.item.streamModel?.mediaInfoTag ?? " ",
      ),
      url: model.media?.url ?? "",
    );
    await player.sendPlayableModel(playableData);
    OxplayerAudioLog.event('native_playable_sent', fields: {
      'backend': 'exo',
      'defaultAudioIndex': playableData.defaultAudioTrack,
      'defaultSubIndex': playableData.defaultSubtrack,
      'audioTrackCount': playableData.audioTracks.length,
      'audioIndexes': playableData.audioTracks.map((t) => t.index).join(','),
      'audioCodecs': playableData.audioTracks.map((t) => t.codec).join(','),
      'startMs': playableData.startPosition,
      'urlLen': playableData.url.length,
    });
  }
}
