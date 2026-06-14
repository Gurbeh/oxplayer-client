import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/offline_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_force_repair_interceptor.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/providers/video_player_provider.dart';

bool oxplayerIsOxStreamUrl(String? url) =>
    url != null && (url.contains('/stream.ts') || url.contains('stream.ts?'));

PlaybackType? _playbackTypeForModel(PlaybackModel model) => switch (model) {
      DirectPlaybackModel _ => PlaybackType.directStream,
      TranscodePlaybackModel _ => PlaybackType.transcode,
      TvPlaybackModel _ => PlaybackType.tv,
      OfflinePlaybackModel _ => PlaybackType.offline,
      _ => null,
    };

/// Holds context for a runtime ox-stream repair while the player is open.
class OxplayerStreamRepairBridge {
  static Ref? ref;
  static PlaybackModel? model;
  static bool runtimeRepairUsed = false;

  static void register(Ref r, PlaybackModel m) {
    ref = r;
    model = m;
    runtimeRepairUsed = false;
  }

  static void clear() {
    ref = null;
    model = null;
    runtimeRepairUsed = false;
  }
}

/// Re-fetches PlaybackInfo with force-repair and rebuilds the playback model.
Future<PlaybackModel?> oxplayerRefreshPlaybackWithForceRepair(
  OxplayerRead read,
  PlaybackModel current, {
  Duration? startPosition,
}) async {
  if (!OxplayerEnv.isEnabled) return null;
  if (current is OfflinePlaybackModel) return null;

  final playbackType = _playbackTypeForModel(current);
  if (playbackType == null) return null;

  read(oxplayerForceRepairNextPlaybackProvider.notifier).state = true;
  return read(playbackModelHelper).createPlaybackModel(
        null,
        current.item,
        oldModel: current,
        libraryQueue: current.queue,
        queueSource: current.queueSource,
        forcedPlaybackType: playbackType,
        startPosition: startPosition,
      );
}

/// One silent retry after initial player load failure (OX stream / missing URL).
Future<bool> oxplayerMaybeRetryPlayAfterLoadFailure({
  required WidgetRef ref,
  required PlaybackModel current,
  required Duration startPosition,
}) async {
  if (!OxplayerEnv.isEnabled) return false;
  if (current is OfflinePlaybackModel) return false;

  final refreshed = await oxplayerRefreshPlaybackWithForceRepair(
    ref.read,
    current,
    startPosition: startPosition,
  );
  if (refreshed == null || refreshed.media?.url == null) return false;

  return ref.read(videoPlayerProvider.notifier).loadPlaybackItem(refreshed, startPosition);
}

/// Called from lib_mpv when ox-stream load retries are exhausted; returns a fresh stream URL once.
Future<String?> oxplayerTryRepairStreamUrl(String deadUrl) async {
  if (!OxplayerEnv.isEnabled || !oxplayerIsOxStreamUrl(deadUrl)) return null;
  if (OxplayerStreamRepairBridge.runtimeRepairUsed) return null;

  final r = OxplayerStreamRepairBridge.ref;
  final model = OxplayerStreamRepairBridge.model;
  if (r == null || model == null) return null;

  OxplayerStreamRepairBridge.runtimeRepairUsed = true;
  final position = r.read(mediaPlaybackProvider).position;
  final refreshed = await oxplayerRefreshPlaybackWithForceRepair(
    r.read,
    model,
    startPosition: position,
  );
  final url = refreshed?.media?.url;
  if (url == null || url == deadUrl) return null;
  if (refreshed != null) {
    OxplayerStreamRepairBridge.model = refreshed;
  }
  return url;
}
