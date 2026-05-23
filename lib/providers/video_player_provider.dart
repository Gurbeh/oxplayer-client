import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/native_playback_trace_log.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_muxed_streams_log.dart';
import 'package:fladder/oxplayer/oxplayer_verified_streams_client.dart';
import 'package:fladder/util/muxed_audio_from_player.dart';
import 'package:fladder/util/muxed_subtitle_from_player.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:fladder/wrappers/players/player_states.dart';

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  videoPlayer.init();
  return videoPlayer;
});

void _oxPlaybackWebLog(String message) {
  if (kDebugMode && kIsWeb) {
    debugPrint('[OX_PLAYBACK_WEB] $message');
  }
}

String _oxPlaybackUrlHint(String url) {
  if (url.isEmpty) return 'empty';
  final uri = Uri.tryParse(url);
  if (uri == null) return 'unparseable len=${url.length}';
  final host = uri.host.isEmpty ? 'none' : uri.host;
  return 'scheme=${uri.scheme.isEmpty ? "none" : uri.scheme} host=$host '
      'pathLen=${uri.path.length} queryKeys=${uri.queryParameters.keys.take(8).join(",")}';
}

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];
  StreamSubscription<List<SubStreamModel>>? _muxedSubtitleDiscoverySubscription;
  StreamSubscription<List<AudioStreamModel>>? _muxedAudioDiscoverySubscription;
  int _muxedDiscoveryGeneration = 0;
  String? _muxedDiscoveryMediaUrl;
  Timer? _verifiedStreamsUploadTimer;
  bool _sawMuxedAudioDiscovery = false;
  bool _sawMuxedSubtitleDiscovery = false;
  bool _nativeEndProgressSynced = false;

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  Future<void> init() async {
    _oxPlaybackWebLog('notifier.init start');
    await state.dispose();
    _oxPlaybackWebLog('notifier.init wrapper disposed');
    await state.init();
    _oxPlaybackWebLog('notifier.init wrapper initialized backend=${state.backend}');
    _nativeEndProgressSynced = false;

    for (final s in subscriptions) {
      s.cancel();
    }
    subscriptions.clear();

    final subscription = state.stateStream?.listen((value) {
      updateBuffering(value.buffering);
      updateBuffer(value.buffer);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
      _handleNativePlaybackCompleted(value);
    });

    if (subscription != null) {
      subscriptions.add(subscription);
      _oxPlaybackWebLog('notifier.init stateStream subscription attached');
    } else {
      _oxPlaybackWebLog('notifier.init stateStream missing');
    }

    _wireMuxedSubtitleDiscovery();
    oxMuxedStreamsLog('VideoPlayerNotifier.init done (mux wiring)');
    _oxPlaybackWebLog('notifier.init done subscriptions=${subscriptions.length}');
  }

  /// When native Exo reaches [PlayerState.completed], push end progress once so Jellyfin
  /// can mark the item watched under normal session rules, even if the user stays on the
  /// last frame before Next Up or back.
  void _handleNativePlaybackCompleted(PlayerState value) {
    if (ref.read(videoPlayerSettingsProvider).wantedPlayer != PlayerOptions.nativePlayer) {
      return;
    }
    if (!value.completed) {
      _nativeEndProgressSynced = false;
      return;
    }
    if (_nativeEndProgressSynced) return;
    _nativeEndProgressSynced = true;
    Future.microtask(() async {
      final model = ref.read(playBackModel);
      if (model == null) return;
      final runTime = model.item.overview.runTime;
      final reported = value.duration > Duration.zero
          ? value.duration
          : ((runTime != null && runTime > Duration.zero) ? runTime : value.position);
      if (reported <= Duration.zero) return;
      try {
        await model.updatePlaybackPosition(reported, false, ref);
      } catch (_) {}
    });
  }

  void _scheduleVerifiedStreamsUpload() {
    if (!OxplayerConfig.isEnabled) return;
    _verifiedStreamsUploadTimer?.cancel();
    _verifiedStreamsUploadTimer = Timer(const Duration(milliseconds: 700), () {
      _verifiedStreamsUploadTimer = null;
      _tryPostVerifiedStreamsManifest();
    });
  }

  Future<void> _tryPostVerifiedStreamsManifest() async {
    if (!OxplayerConfig.isEnabled) {
      oxMuxedStreamsLog('verified POST: skip OxplayerConfig.isEnabled=false');
      return;
    }
    final expectUrl = _muxedDiscoveryMediaUrl;
    if (expectUrl == null) {
      oxMuxedStreamsLog('verified POST: skip _muxedDiscoveryMediaUrl=null');
      return;
    }
    if (!_sawMuxedAudioDiscovery && !_sawMuxedSubtitleDiscovery) {
      oxMuxedStreamsLog('verified POST: skip no mux discovery flags yet');
      return;
    }

    final playback = ref.read(playBackModel);
    if (playback == null || playback.media?.url != expectUrl) {
      oxMuxedStreamsLog(
        'verified POST: skip playback=${playback == null} or url no longer matches session',
      );
      return;
    }

    final mediaId =
        playback.media?.libraryMediaFileId ?? parseOxplayerTelegramMediaId(expectUrl);
    if (mediaId == null) {
      oxMuxedStreamsLog(
        'verified POST: skip no libraryMediaFileId (set when Path is oxplayer://telegram/…) '
        'and URL is not oxplayer scheme=${Uri.tryParse(expectUrl)?.scheme} len=${expectUrl.length}',
      );
      return;
    }

    final vs = playback.mediaStreams?.currentVersionStream;
    if (vs == null) {
      oxMuxedStreamsLog('verified POST: skip no currentVersionStream');
      return;
    }

    final audio =
        vs.audioStreams.where((a) => !a.isExternal && a.demuxerTrackId != null).toList();
    final subtitles = _sawMuxedSubtitleDiscovery
        ? vs.subStreams.where((s) => !s.isExternal && s.index >= 0).toList()
        : <SubStreamModel>[];

    if (audio.isEmpty && subtitles.isEmpty) {
      oxMuxedStreamsLog(
        'verified POST: skip empty payload audio=${audio.length} subs=${subtitles.length} '
        'sawSub=$_sawMuxedSubtitleDiscovery sawAud=$_sawMuxedAudioDiscovery',
      );
      return;
    }

    oxMuxedStreamsLog(
      'verified POST: calling API mediaId=$mediaId audio=${audio.length} subs=${subtitles.length}',
    );
    await postVerifiedStreamsManifestIfNeeded(
      ref,
      mediaId: mediaId,
      audio: audio,
      subtitles: subtitles,
    );
  }

  void _wireMuxedSubtitleDiscovery() {
    _muxedAudioDiscoverySubscription?.cancel();
    _muxedAudioDiscoverySubscription = null;
    final audioStream = state.muxedAudioDiscoveryStream;
    if (audioStream != null) {
      _muxedAudioDiscoverySubscription = audioStream.listen(
        _onMuxedAudioTracksDiscovered,
        onError: (Object e, _) => oxMuxedStreamsLog('muxedAudio stream error: $e'),
      );
    }
    _muxedSubtitleDiscoverySubscription?.cancel();
    _muxedSubtitleDiscoverySubscription = null;
    final stream = state.muxedSubtitleDiscoveryStream;
    final backend = state.backend;
    if (stream == null) {
      oxMuxedStreamsLog(
        'wire mux discovery: subtitle stream is null (backend=$backend; e.g. NativePlayer, or player disposed between dispose/init)',
      );
      return;
    }
    oxMuxedStreamsLog('wire mux discovery: backend=$backend sub+audio listeners attached');
    _muxedSubtitleDiscoverySubscription = stream.listen(
      _onMuxedSubtitleTracksDiscovered,
      onError: (Object e, _) => oxMuxedStreamsLog('muxedSubtitle stream error: $e'),
    );
  }

  Future<void> _onMuxedAudioTracksDiscovered(List<AudioStreamModel> muxed) async {
    if (muxed.isEmpty) {
      oxMuxedStreamsLog('muxedAudio event: empty list (ignored)');
      return;
    }
    oxMuxedStreamsLog('muxedAudio event: count=${muxed.length} gen=$_muxedDiscoveryGeneration');
    final token = _muxedDiscoveryGeneration;
    final expectedUrl = _muxedDiscoveryMediaUrl;
    final playback = ref.read(playBackModel);
    if (playback == null) {
      oxMuxedStreamsLog('muxedAudio: abort playback=null');
      return;
    }
    if (expectedUrl != null && playback.media?.url != expectedUrl) {
      oxMuxedStreamsLog(
        'muxedAudio: abort url mismatch expect=${expectedUrl.length} actual=${(playback.media?.url ?? '').length}',
      );
      return;
    }
    final ms = playback.mediaStreams;
    if (!muxedAudioListChanged(ms, muxed)) return;
    final merged = ms?.mergeMuxedAudioStreamsFromContainer(muxed);
    if (merged == null) {
      oxMuxedStreamsLog('muxedAudio: abort merge returned null');
      return;
    }
    final updated = playbackWithMergedMediaStreams(playback, merged);
    if (updated == null) return;
    oxMuxedStreamsLog(
      'muxedAudio applied defaultAudio=${merged.defaultAudioStreamIndex} '
      'audioRows=${merged.audioStreams.length}',
    );
    ref.read(playBackModel.notifier).update((_) => updated);
    if (token != _muxedDiscoveryGeneration) return;
    if (expectedUrl != null && updated.media?.url != expectedUrl) return;
    await state.setAudioTrack(null, updated);
    _sawMuxedAudioDiscovery = true;
    _scheduleVerifiedStreamsUpload();
    await state.syncNativePlaybackAfterMuxMerge(updated);
  }

  Future<void> _onMuxedSubtitleTracksDiscovered(List<SubStreamModel> muxed) async {
    if (muxed.isEmpty) {
      oxMuxedStreamsLog('muxedSubtitle event: empty list (ignored)');
      return;
    }
    oxMuxedStreamsLog('muxedSubtitle event: count=${muxed.length} gen=$_muxedDiscoveryGeneration');
    final token = _muxedDiscoveryGeneration;
    final expectedUrl = _muxedDiscoveryMediaUrl;
    final playback = ref.read(playBackModel);
    if (playback == null) {
      oxMuxedStreamsLog('muxedSubtitle: abort playback=null');
      return;
    }
    if (expectedUrl != null && playback.media?.url != expectedUrl) {
      oxMuxedStreamsLog(
        'muxedSubtitle: abort url mismatch expect=${expectedUrl.length} actual=${(playback.media?.url ?? '').length}',
      );
      return;
    }
    final ms = playback.mediaStreams;
    if (!muxedSubtitleListChanged(ms, muxed)) return;
    final merged = ms?.mergeMuxedSubtitleStreamsFromContainer(muxed);
    if (merged == null) {
      oxMuxedStreamsLog('muxedSubtitle: abort merge returned null');
      return;
    }
    final updated = playbackWithMergedMediaStreams(playback, merged);
    if (updated == null) return;
    oxMuxedStreamsLog(
      'muxedSubtitle applied defaultSub=${merged.defaultSubStreamIndex} '
      'subRows=${merged.subStreams.length}',
    );
    ref.read(playBackModel.notifier).update((_) => updated);
    if (token != _muxedDiscoveryGeneration) return;
    if (expectedUrl != null && updated.media?.url != expectedUrl) return;
    await state.setSubtitleTrack(null, updated);
    _sawMuxedSubtitleDiscovery = true;
    _scheduleVerifiedStreamsUpload();
    await state.syncNativePlaybackAfterMuxMerge(updated);
  }

  Future<void> updateBuffering(bool event) async =>
      mediaState.update((state) => state.buffering == event ? state : state.copyWith(buffering: event));

  Future<void> updateBuffer(Duration buffer) async {
    mediaState.update(
      (state) => (state.buffer - buffer).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              buffer: buffer,
            ),
    );
  }

  Future<void> updateDuration(Duration duration) async {
    mediaState.update((state) {
      // libmpv can emit 0 briefly over loopback/HTTP while demuxing; do not clobber a
      // duration we already have (e.g. seeded from Telegram or a prior probe).
      if (duration <= Duration.zero && state.duration > const Duration(seconds: 5)) {
        return state;
      }
      return (state.duration - duration).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              duration: duration,
            );
    });
  }

  Future<void> updatePlaying(bool event) async {
    final currentState = playbackState;
    if (!state.hasPlayer || currentState.playing == event) return;
    if (currentState.state == VideoPlayerState.disposed) return;
    mediaState.update(
      (state) => state.copyWith(playing: event),
    );
    ref.read(playBackModel)?.updatePlaybackPosition(currentState.position, currentState.playing, ref);
  }

  Future<void> updatePosition(Duration event) async {
    if (!state.hasPlayer) return;
    if (playbackState.playing == false) return;
    final currentState = playbackState;
    if (currentState.state == VideoPlayerState.disposed) return;
    final currentPosition = currentState.position;

    if ((currentPosition - event).inSeconds.abs() < 1) return;

    final position = event;

    final lastPosition = currentState.lastPosition;
    final diff = (position.inMilliseconds - lastPosition.inMilliseconds).abs();

    if (diff > const Duration(seconds: 10).inMilliseconds) {
      mediaState.update((value) => value.copyWith(
            position: event,
            lastPosition: position,
          ));
      ref.read(playBackModel)?.updatePlaybackPosition(position, playbackState.playing, ref);
    } else {
      mediaState.update((value) => value.copyWith(
            position: event,
          ));
    }
  }

  Future<bool> loadPlaybackItem(PlaybackModel model, Duration startPosition) async {
    _oxPlaybackWebLog(
      'notifier.loadPlaybackItem ENTER itemId=${model.item.id} '
      'name="${model.item.name}" startMs=${startPosition.inMilliseconds}',
    );
    _nativeEndProgressSynced = false;
    _muxedDiscoveryGeneration++;
    _muxedDiscoveryMediaUrl = model.media?.url;
    _sawMuxedAudioDiscovery = false;
    _sawMuxedSubtitleDiscovery = false;
    _verifiedStreamsUploadTimer?.cancel();
    _verifiedStreamsUploadTimer = null;
    final u = model.media?.url ?? '';
    final wantedPlayer = ref.read(videoPlayerSettingsProvider).wantedPlayer;
    _oxPlaybackWebLog(
      'notifier.loadPlaybackItem model media=${model.media.runtimeType} '
      'wanted=$wantedPlayer backend=${state.backend} ${_oxPlaybackUrlHint(u)} '
      'streams audio=${model.mediaStreams?.audioStreams.length ?? 0} '
      'subs=${model.mediaStreams?.subStreams.length ?? 0}',
    );
    oxNativePlaybackTrace(
      'VideoPlayerNotifier.loadPlaybackItem itemId=${model.item.id} name=${model.item.name} '
      'wantedPlayer=$wantedPlayer startMs=${startPosition.inMilliseconds} ${oxNativePlaybackUrlHint(u)}',
    );
    oxMuxedStreamsLog(
      'loadPlaybackItem gen=$_muxedDiscoveryGeneration ox=${OxplayerConfig.isEnabled} '
      'backend=${state.backend} urlScheme=${Uri.tryParse(u)?.scheme ?? "?"} '
      'libraryMediaFileId=${model.media?.libraryMediaFileId ?? "null"} '
      'subRows=${model.mediaStreams?.subStreams.length ?? 0}',
    );
    ref.read(playBackModel)?.dispose();
    final nextUrl = model.media?.url ?? '';
    final nextUsesOxLoopback = nextUrl.contains('127.0.0.1') || nextUrl.contains('__ox_tdweb_stream');
    _oxPlaybackWebLog(
      'notifier.loadPlaybackItem stopWithPlaybackOptions releaseCache=${!nextUsesOxLoopback}',
    );
    try {
      await state.stopWithPlaybackOptions(releaseOxTelegramCache: !nextUsesOxLoopback);
      _oxPlaybackWebLog('notifier.loadPlaybackItem stopWithPlaybackOptions ok');
    } catch (error, stackTrace) {
      _oxPlaybackWebLog('notifier.loadPlaybackItem stopWithPlaybackOptions ERROR $error\n$stackTrace');
      rethrow;
    }
    ref.read(playbackRateProvider.notifier).state = 1.0;
    mediaState.update((state) => state.copyWith(
          state: VideoPlayerState.fullScreen,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        ));

    final media = model.media;
    PlaybackModel? newPlaybackModel = model;

    if (media != null) {
      ref.read(playBackModel.notifier).update((_) => newPlaybackModel);
      _oxPlaybackWebLog('notifier.loadPlaybackItem playBackModel set; calling wrapper.loadVideo');
      oxNativePlaybackTrace('VideoPlayerNotifier.loadPlaybackItem calling state.loadVideo');
      try {
        await state.loadVideo(model, startPosition, true);
        _oxPlaybackWebLog('notifier.loadPlaybackItem wrapper.loadVideo ok');
      } catch (error, stackTrace) {
        _oxPlaybackWebLog('notifier.loadPlaybackItem wrapper.loadVideo ERROR $error\n$stackTrace');
        rethrow;
      }
      try {
        await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);
        _oxPlaybackWebLog('notifier.loadPlaybackItem setVolume ok');
      } catch (error, stackTrace) {
        _oxPlaybackWebLog('notifier.loadPlaybackItem setVolume ERROR $error\n$stackTrace');
        rethrow;
      }

      try {
        await state.setAudioTrack(null, model);
        _oxPlaybackWebLog('notifier.loadPlaybackItem setAudioTrack ok');
      } catch (error, stackTrace) {
        _oxPlaybackWebLog('notifier.loadPlaybackItem setAudioTrack ERROR $error\n$stackTrace');
        rethrow;
      }
      try {
        await state.setSubtitleTrack(null, model);
        _oxPlaybackWebLog('notifier.loadPlaybackItem setSubtitleTrack ok');
      } catch (error, stackTrace) {
        _oxPlaybackWebLog('notifier.loadPlaybackItem setSubtitleTrack ERROR $error\n$stackTrace');
        rethrow;
      }

      try {
        await state.play();
        _oxPlaybackWebLog('notifier.loadPlaybackItem play ok');
      } catch (error, stackTrace) {
        _oxPlaybackWebLog('notifier.loadPlaybackItem play ERROR $error\n$stackTrace');
        rethrow;
      }
      _wireMuxedSubtitleDiscovery();
      oxMuxedStreamsLog('loadPlaybackItem finished play(); mux discovery re-wired');
      oxNativePlaybackTrace('VideoPlayerNotifier.loadPlaybackItem success=true');
      _oxPlaybackWebLog('notifier.loadPlaybackItem SUCCESS');
      return true;
    }

    oxNativePlaybackTrace('VideoPlayerNotifier.loadPlaybackItem FAIL media==null');
    _oxPlaybackWebLog('notifier.loadPlaybackItem FAIL media=null');
    mediaState.update((state) => state.copyWith(errorPlaying: true));
    return false;
  }

  Future<void> openPlayer(BuildContext context) async => state.openPlayer(context);

  Future<bool> takeScreenshot() async {
    final syncPath = ref.read(clientSettingsProvider).syncPath;
    // Early return here if we don't have a set/valid path. Skips actually taking the screenshot
    // which would be discarded.
    if (syncPath == null) {
      return false;
    }

    final screenshotsPath = p.join(syncPath, "Screenshots");
    final screenshotBuf = await state.takeScreenshot();

    if (screenshotBuf != null) {
      final savePathDirectory = Directory(screenshotsPath);

      // Should we try to create the directory instead?
      if (!await savePathDirectory.exists()) {
        return false;
      }

      final fileExtension = "png";
      final paddingAmount = 3;

      int maxNumber = 0;

      await for (var file in savePathDirectory.list()) {
        final finalSegment = file.uri.pathSegments.last;

        if (file is File && p.extension(finalSegment) == ".$fileExtension") {
          final match = RegExp(r'(\d+)').firstMatch(finalSegment);

          if (match != null) {
            final fileNumber = int.parse(match.group(0)!);

            if (fileNumber > maxNumber) {
              maxNumber = fileNumber;
            }
          }
        }
      }

      maxNumber += 1;

      final maxNumberStr = maxNumber.toString().padLeft(paddingAmount, '0');
      final screenshotName = '$maxNumberStr.$fileExtension';
      final screenshotPath = p.join(screenshotsPath, screenshotName);

      final screenshotFile = File(screenshotPath);
      await screenshotFile.writeAsBytes(screenshotBuf);

      return true;
    }

    return false;
  }
}
