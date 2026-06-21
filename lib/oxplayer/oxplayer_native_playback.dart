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

/// Intentionally disabled: launching the activity before [loadPlaybackItem] causes ExoPlayer
/// to bind and sit idle while Dart finishes stop()/network work. The user sees a black screen
/// and presses Back before the URL arrives. The standard flow (openPlayer after loadPlaybackItem)
/// is correct: pendingOpenUrl is set by open(), then init() picks it up when ExoPlayer binds.
Future<bool> oxplayerOpenNativePlayerEarly(WidgetRef ref, BuildContext context) async {
  return false;
}

/// After load, detect a stuck 00:00 / no-progress state and report + retry once.
Timer? oxplayerScheduleNativeStuckPlaybackWatch({
  required WidgetRef ref,
  required String itemId,
  required String? streamUrl,
  Duration? catalogDuration,
}) {
  if (!oxplayerUsesNativePlayer(ref)) return null;

  return Timer(const Duration(seconds: 12), () async {
    // Detail screen may be popped; use session ref registered during loadPlaybackItem.
    final sessionRef = OxplayerStreamRepairBridge.ref;
    if (sessionRef == null) return;

    final playback = sessionRef.read(mediaPlaybackProvider);
    final model = sessionRef.read(playBackModel);
    if (model == null || model.item.id != itemId) return;

    final stuck = !playback.playing &&
        playback.position <= const Duration(seconds: 1) &&
        (playback.duration <= Duration.zero ||
            (catalogDuration != null && playback.duration <= const Duration(seconds: 1)));

    if (!stuck) return;

    unawaited(OxplayerPlaybackTelemetry.reportStuckPlayback(
      itemId: itemId,
      streamUrl: streamUrl,
      position: playback.position,
      catalogDuration: catalogDuration,
      nativePlayer: true,
    ));

    // One silent reload with force-repair when stream is not ready yet.
    final start = playback.position;
    final refreshed = await oxplayerRefreshPlaybackWithForceRepair(
      sessionRef.read,
      model,
      startPosition: start,
    );
    final retryModel = refreshed ?? model;
    await sessionRef.read(videoPlayerProvider.notifier).loadPlaybackItem(retryModel, start);
  });
}
