import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/oxplayer/oxplayer_playback_audio.dart';
import 'package:fladder/oxplayer/oxplayer_playback_subtitle.dart';
import 'package:fladder/oxplayer/oxplayer_audio_log.dart';
import 'package:collection/collection.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_memory_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_native_playback.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  videoPlayer.init();
  return videoPlayer;
});

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  Future<void> init() async {
    final settings = ref.read(videoPlayerSettingsProvider);
    if (state.hasPlayer && state.matchesSettings(settings)) {
      return;
    }

    OxplayerStreamLog.event('video_player_reinit', fields: {
      'hasPlayer': state.hasPlayer,
      'stack': StackTrace.current.toString().split('\n').take(8).join(' <- '),
    });

    await state.dispose();
    await state.init();

    for (final s in subscriptions) {
      s.cancel();
    }

    final subscription = state.stateStream.listen((value) {
      updateBuffering(value.buffering);
      updateBuffer(value.buffer);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
    });

    subscriptions.add(subscription);
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
    final catalog = ref.read(playBackModel)?.item.overview.runTime;
    if (duration == Duration.zero && catalog != null && catalog > Duration.zero) {
      duration = catalog;
    }
    mediaState.update((state) {
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

    final progressThreshold = OxplayerEnv.isEnabled
        ? const Duration(seconds: 30)
        : const Duration(seconds: 10);
    if (diff > progressThreshold.inMilliseconds) {
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
    if (OxplayerEnv.isEnabled) {
      OxplayerStreamLog.event('player_load_start', fields: {
        'itemId': model.item.id,
        'hasMedia': model.media != null,
        'hasPlayer': state.hasPlayer,
      });
    }

    if (!state.hasPlayer) {
      await init();
    }

    ref.read(playBackModel)?.dispose();
    await state.stop();
    ref.read(playbackRateProvider.notifier).state = 1.0;

    if (OxplayerEnv.isEnabled && oxplayerUsesNativePlayerRead(ref)) {
      OxplayerMemoryTelemetry.trimBeforeNativePlayback();
    }

    final useMinimizedPlayer =
        model.item.type == FladderItemType.audio || model.mediaStreams?.videoStreams.isEmpty == true;

    mediaState.update((state) => state.copyWith(
          state: useMinimizedPlayer ? VideoPlayerState.minimized : VideoPlayerState.fullScreen,
          fullScreen: !useMinimizedPlayer,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        ));

    final media = model.media;
    PlaybackModel? newPlaybackModel = model;
    final effectiveStartPosition = await model.resolvedStartPosition(startPosition);

    if (media != null) {
      OxplayerStreamLog.event('player_load', fields: {
        'itemId': model.item.id,
        'startPosition': OxplayerStreamLog.formatDuration(effectiveStartPosition),
        'startMs': effectiveStartPosition.inMilliseconds,
        'streamUrl': OxplayerStreamLog.describeUrl(media.url),
        'streamHost': OxplayerStreamLog.describeHost(media.url),
      });
      ref.read(playBackModel.notifier).update((state) => newPlaybackModel);
      await state.loadVideo(model, effectiveStartPosition, true);
      final settingsVolume = ref.read(videoPlayerSettingsProvider).volume;
      final backend = ref.read(videoPlayerSettingsProvider).wantedPlayer;
      OxplayerAudioLog.event('playback_load_volume', fields: {
        'backend': backend.name,
        'settingsVolume': settingsVolume,
        'defaultAudioIndex': model.mediaStreams?.defaultAudioStreamIndex,
        'audioStreamCount': model.audioStreams?.length,
        'audioIndexes': model.audioStreams?.map((s) => s.index).join(','),
        'resolvedAudioIndex': oxplayerResolvePlaybackAudioStream(model)?.index,
        'enablePlayPauseFade': ref.read(videoPlayerSettingsProvider).enablePlayPauseFade,
      });
      await state.setVolume(settingsVolume);

      final resolvedAudio = oxplayerResolvePlaybackAudioStream(model);
      await state.setAudioTrack(resolvedAudio, model);
      final resolvedSubIndex = oxplayerResolveSubtitleStreamIndex(
        selectedIndex: model.mediaStreams?.defaultSubStreamIndex,
        serverDefaultIndex: model.mediaStreams?.defaultSubStreamIndex,
        subStreams: model.subStreams,
      );
      final resolvedSub = model.subStreams?.firstWhereOrNull((s) => s.index == resolvedSubIndex);
      // Route through PlaybackModel.setSubtitle (not state.setSubtitleTrack directly) so
      // mediaStreams.defaultSubStreamIndex reflects what auto-selection (e.g. preferred Persian
      // track) actually applied to the player — otherwise the subtitle picker UI keeps showing
      // "Off" as selected while a real subtitle is playing, since nothing ever wrote the resolved
      // index back onto the model the UI reads.
      final subtitleAppliedModel = await newPlaybackModel.setSubtitle(resolvedSub, state);
      if (subtitleAppliedModel != null) {
        newPlaybackModel = subtitleAppliedModel;
        ref.read(playBackModel.notifier).update((state) => newPlaybackModel);
      }

      final runtime = model.item.overview.runTime;
      final deferCatalogDuration = OxplayerEnv.isEnabled && oxplayerUsesNativePlayerRead(ref);
      ref.read(mediaPlaybackProvider.notifier).update((playback) {
        var next = playback.copyWith(
          state: useMinimizedPlayer ? VideoPlayerState.minimized : VideoPlayerState.fullScreen,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        );
        if (OxplayerEnv.isEnabled) {
          next = next.copyWith(
            position: effectiveStartPosition,
            lastPosition: effectiveStartPosition,
          );
          if (!deferCatalogDuration && runtime != null && runtime > Duration.zero) {
            next = next.copyWith(duration: runtime);
          }
        }
        return next;
      });

      await state.play();

      if (OxplayerEnv.isEnabled) {
        OxplayerStreamRepairBridge.register(ref, newPlaybackModel);
        final runtime = model.item.overview.runTime;
        // Keep buffering=true until ExoPlayer reports STATE_READY — premature false
        // triggers stuck-repair loops during CDN resume seek (UI position already advanced).
        mediaState.update((state) {
          var next = state.copyWith(
            position: effectiveStartPosition,
            lastPosition: effectiveStartPosition,
          );
          if (!deferCatalogDuration && runtime != null) {
            next = next.copyWith(duration: runtime);
          }
          return next;
        });
      }

      return true;
    }

    mediaState.update((state) => state.copyWith(errorPlaying: true));
    unawaited(OxplayerPlaybackTelemetry.reportFailure(
      stage: 'player_load',
      reason: 'missing_media_url',
      itemId: model.item.id,
    ));
    return false;
  }

  Future<bool> loadAudioPlaybackItem(
    PlaybackModel model,
    List<ItemBaseModel> queue,
    int currentIndex,
    Duration startPosition,
  ) async {
    final currentPlayerState = ref.read(mediaPlaybackProvider).state;
    final keepFullScreenLayout = currentPlayerState == VideoPlayerState.fullScreen;
    final playbackSettings = ref.read(mediaPlaybackProvider);

    final initializedQueueState = PlaybackQueueState.fromQueue(
      queue,
      initialItemId: queue[currentIndex.clamp(0, queue.length - 1)].id,
      shuffleEnabled: playbackSettings.shuffleEnabled,
      repeatMode: playbackSettings.repeatMode,
    );
    final queuedModel = model.updatePlaybackQueue(initializedQueueState);
    final effectiveStartPosition = await queuedModel.resolvedStartPosition(startPosition);

    ref.read(playBackModel.notifier).update((state) => queuedModel);
    ref.read(playbackRateProvider.notifier).state = 1.0;

    mediaState.update((state) => state.copyWith(
          state: keepFullScreenLayout ? VideoPlayerState.fullScreen : VideoPlayerState.minimized,
          fullScreen: keepFullScreenLayout,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));

    await state.loadAudioQueue(queue, currentIndex, effectiveStartPosition, true);
    await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);

    mediaState.update((state) => state.copyWith(
          buffering: false,
          playing: true,
          position: effectiveStartPosition,
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));
    return true;
  }

  Future<void> reorderAudioQueueSection(
    AudioQueueSection section,
    int oldIndex,
    int newIndex,
  ) async {
    await state.reorderAudioQueueSection(section, oldIndex, newIndex);
  }

  Future<void> addToTemporaryQueue(List<ItemBaseModel> items) async {
    await state.addToTemporaryQueue(items);
  }

  Future<void> clearTemporaryQueue() async {
    state.clearTemporaryQueue();
  }

  Future<void> removeAudioQueueItem(ItemBaseModel item) async {
    await state.removeAudioQueueItem(item.id);
  }

  Future<void> removeAudioQueueSectionItem(
    AudioQueueSection section,
    int sectionIndex,
  ) async {
    await state.removeAudioQueueSectionItem(section, sectionIndex);
  }

  Future<void> playAudioQueueItem(ItemBaseModel item) async {
    if (ref.read(playBackModel) == null) return;
    await state.jumpToQueueItem(item);
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
