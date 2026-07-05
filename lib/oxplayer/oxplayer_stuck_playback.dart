import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

export 'package:fladder/oxplayer/oxplayer_stuck_playback.dart' show
    oxplayerNativePlaybackLooksStuck,
    oxplayerPlaybackLooksFrozenMidStream,
    oxplayerOpenNativePlayerEarly,
    oxplayerScheduleStuckPlaybackWatch,
    oxplayerUsesNativePlayer,
    oxplayerUsesNativePlayerRead,
    oxplayerUsesMpvPlayerOnAndroid,
    oxplayerUsesMpvPlayerOnAndroidRead;

/// True when the Android native (ExoPlayer) backend is selected.
bool oxplayerUsesNativePlayer(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

bool oxplayerUsesNativePlayerRead(Ref ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

/// True when Android uses in-app MPV (typical phone/tablet layout).
bool oxplayerUsesMpvPlayerOnAndroid(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.libMPV;
}

bool oxplayerUsesMpvPlayerOnAndroidRead(Ref ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.libMPV;
}

bool _shouldScheduleStuckWatch(WidgetRef ref) {
  return oxplayerUsesNativePlayer(ref) || oxplayerUsesMpvPlayerOnAndroid(ref);
}

/// Intentionally disabled: launching the activity before [loadPlaybackItem] causes ExoPlayer
/// to bind and sit idle while Dart finishes stop()/network work. The user sees a black screen
/// and presses Back before the URL arrives. The standard flow (openPlayer after loadPlaybackItem)
/// is correct: pendingOpenUrl is set by open(), then init() picks it up when ExoPlayer binds.
Future<bool> oxplayerOpenNativePlayerEarly(WidgetRef ref, BuildContext context) async {
  return false;
}

const stuckPlaybackCheckDelay = Duration(seconds: 12);
const _maxStuckRetries = 3;

/// True when the player appears idle right after open (not merely buffering a cold stream).
@visibleForTesting
bool oxplayerNativePlaybackLooksStuck({
  required bool playing,
  required bool buffering,
  required Duration position,
  required Duration buffer,
  Duration startPosition = Duration.zero,
}) {
  if (buffering || playing) return false;
  // Buffer head advancing means the stream is alive even if position is still near zero.
  if (buffer > const Duration(seconds: 2)) return false;
  return position <= startPosition + const Duration(seconds: 2);
}

/// True when playback claims to be active but timeline/buffer head stopped advancing.
@visibleForTesting
bool oxplayerPlaybackLooksFrozenMidStream({
  required bool playing,
  required bool buffering,
  required Duration position,
  required Duration previousPosition,
  required Duration buffer,
  required Duration previousBuffer,
  Duration? duration,
  Duration startPosition = Duration.zero,
}) {
  if (buffering || !playing) return false;

  final positionMoved = (position - previousPosition).inSeconds.abs() >= 1;
  final bufferMoved = (buffer - previousBuffer).inSeconds.abs() >= 1;
  if (positionMoved || bufferMoved) return false;

  if (position <= startPosition + const Duration(seconds: 5)) return false;

  if (duration != null && duration > Duration.zero) {
    if (position >= duration - const Duration(seconds: 10)) return false;
  }

  return true;
}

/// Periodically detects start-stuck and mid-stream freeze on Android native + MPV; auto-repairs.
Timer? oxplayerScheduleStuckPlaybackWatch({
  required WidgetRef ref,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
  Duration startPosition = Duration.zero,
}) {
  if (!_shouldScheduleStuckWatch(ref)) return null;

  var retriesUsed = 0;
  var telemetrySentForIncident = false;
  var exhaustedReported = false;
  Timer? timer;
  var previousPosition = startPosition;
  var previousBuffer = Duration.zero;

  Future<void> runStuckCheck() async {
    final sessionRef = OxplayerStreamRepairBridge.ref;
    if (sessionRef == null) {
      timer?.cancel();
      return;
    }

    final playback = sessionRef.read(mediaPlaybackProvider);
    final model = sessionRef.read(playBackModel);
    if (model == null || model.item.id != itemId) {
      timer?.cancel();
      return;
    }

    final startStuck = oxplayerNativePlaybackLooksStuck(
      playing: playback.playing,
      buffering: playback.buffering,
      position: playback.position,
      buffer: playback.buffer,
      startPosition: startPosition,
    );
    final midStreamFrozen = oxplayerPlaybackLooksFrozenMidStream(
      playing: playback.playing,
      buffering: playback.buffering,
      position: playback.position,
      previousPosition: previousPosition,
      buffer: playback.buffer,
      previousBuffer: previousBuffer,
      duration: playback.duration.inSeconds > 0 ? playback.duration : catalogDuration,
      startPosition: startPosition,
    );

    previousPosition = playback.position;
    previousBuffer = playback.buffer;

    final stuck = startStuck || midStreamFrozen;
    if (!stuck) {
      retriesUsed = 0;
      telemetrySentForIncident = false;
      exhaustedReported = false;
      timer = Timer(stuckPlaybackCheckDelay, () => unawaited(runStuckCheck()));
      return;
    }

    if (retriesUsed >= _maxStuckRetries) {
      if (!exhaustedReported) {
        exhaustedReported = true;
        unawaited(OxplayerPlaybackTelemetry.reportFailure(
          stage: 'player_stuck',
          reason: midStreamFrozen ? 'mid_stream_exhausted_retries' : 'zero_progress_exhausted_retries',
          itemId: itemId,
          streamUrl: streamUrl,
          extra: {'retries': retriesUsed},
        ));
      }
      timer = Timer(stuckPlaybackCheckDelay, () => unawaited(runStuckCheck()));
      return;
    }

    if (!telemetrySentForIncident) {
      telemetrySentForIncident = true;
      unawaited(OxplayerPlaybackTelemetry.reportStuckPlayback(
        itemId: itemId,
        streamUrl: streamUrl,
        position: playback.position,
        catalogDuration: catalogDuration,
        nativePlayer: oxplayerUsesNativePlayerRead(sessionRef),
        stuckKind: midStreamFrozen ? 'mid_stream' : 'start',
        transient: midStreamFrozen ? false : true,
      ));
    }

    retriesUsed++;
    final resumeAt = playback.position;
    final refreshed = await oxplayerRefreshPlaybackWithForceRepair(
      sessionRef.read,
      model,
      startPosition: resumeAt,
    );
    final retryModel = refreshed ?? model;
    await sessionRef.read(videoPlayerProvider.notifier).loadPlaybackItem(retryModel, resumeAt);

    timer = Timer(stuckPlaybackCheckDelay, () => unawaited(runStuckCheck()));
  }

  timer = Timer(stuckPlaybackCheckDelay, () => unawaited(runStuckCheck()));
  return timer;
}

/// Back-compat alias.
Timer? oxplayerScheduleNativeStuckPlaybackWatch({
  required WidgetRef ref,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
  Duration startPosition = Duration.zero,
}) =>
    oxplayerScheduleStuckPlaybackWatch(
      ref: ref,
      itemId: itemId,
      streamUrl: streamUrl,
      catalogDuration: catalogDuration,
      startPosition: startPosition,
    );
