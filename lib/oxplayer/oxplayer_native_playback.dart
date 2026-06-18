import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

/// True when the Android native (ExoPlayer) backend is selected.
bool oxplayerUsesNativePlayer(WidgetRef ref) {
  if (kIsWeb || !Platform.isAndroid || !OxplayerConfig.isEnabled) return false;
  return ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.nativePlayer;
}

/// Launch the native player activity before loading media so ExoPlayer exists when [open] runs.
Future<bool> oxplayerOpenNativePlayerEarly(WidgetRef ref, BuildContext context) async {
  if (!oxplayerUsesNativePlayer(ref) || !context.mounted) return false;
  await ref.read(videoPlayerProvider.notifier).openPlayer(context);
  // Compose + ExoPlayer init on TV can lag behind the activity transition.
  await Future<void>.delayed(const Duration(milliseconds: 450));
  return true;
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
    final playback = ref.read(mediaPlaybackProvider);
    final model = ref.read(playBackModel);
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

    // One silent reload — matches user workaround of closing and reopening.
    final start = playback.position;
    await ref.read(videoPlayerProvider.notifier).loadPlaybackItem(model, start);
  });
}
