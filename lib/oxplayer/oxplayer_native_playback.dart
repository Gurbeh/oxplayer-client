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

/// True when the Android native (ExoPlayer) backend is selected.
bool oxplayerUsesNativePlayer(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

bool oxplayerUsesNativePlayerRead(Ref ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

/// Intentionally disabled: launching the activity before [loadPlaybackItem] causes ExoPlayer
/// to bind and sit idle while Dart finishes stop()/network work. The user sees a black screen
/// and presses Back before the URL arrives. The standard flow (openPlayer after loadPlaybackItem)
/// is correct: pendingOpenUrl is set by open(), then init() picks it up when ExoPlayer binds.
Future<bool> oxplayerOpenNativePlayerEarly(WidgetRef ref, BuildContext context) async {
  return false;
}

const _stuckCheckDelay = Duration(seconds: 12);
const _maxStuckRetries = 3;

/// True when ExoPlayer appears idle after load (not merely buffering a cold stream).
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

/// After the player opens, detect 00:00 / no-progress on Android TV and auto-retry with force-repair.
Timer? oxplayerScheduleNativeStuckPlaybackWatch({
  required WidgetRef ref,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
  Duration startPosition = Duration.zero,
}) {
  if (!oxplayerUsesNativePlayer(ref)) return null;

  var retriesUsed = 0;
  Timer? timer;

  Future<void> runStuckCheck() async {
    final sessionRef = OxplayerStreamRepairBridge.ref;
    if (sessionRef == null) return;

    final playback = sessionRef.read(mediaPlaybackProvider);
    final model = sessionRef.read(playBackModel);
    if (model == null || model.item.id != itemId) return;

    final stuck = oxplayerNativePlaybackLooksStuck(
      playing: playback.playing,
      buffering: playback.buffering,
      position: playback.position,
      buffer: playback.buffer,
      startPosition: startPosition,
    );
    if (!stuck) return;

    if (retriesUsed == 0) {
      unawaited(OxplayerPlaybackTelemetry.reportStuckPlayback(
        itemId: itemId,
        streamUrl: streamUrl,
        position: playback.position,
        catalogDuration: catalogDuration,
        nativePlayer: true,
      ));
    }

    if (retriesUsed >= _maxStuckRetries) {
      unawaited(OxplayerPlaybackTelemetry.reportFailure(
        stage: 'player_stuck',
        reason: 'zero_progress_exhausted_retries',
        itemId: itemId,
        streamUrl: streamUrl,
        extra: {'retries': retriesUsed},
      ));
      return;
    }

    retriesUsed++;
    final start = playback.position;
    final refreshed = await oxplayerRefreshPlaybackWithForceRepair(
      sessionRef.read,
      model,
      startPosition: start,
    );
    final retryModel = refreshed ?? model;
    await sessionRef.read(videoPlayerProvider.notifier).loadPlaybackItem(retryModel, start);
    timer?.cancel();
    timer = Timer(_stuckCheckDelay, () => unawaited(runStuckCheck()));
  }

  timer = Timer(_stuckCheckDelay, () => unawaited(runStuckCheck()));
  return timer;
}
