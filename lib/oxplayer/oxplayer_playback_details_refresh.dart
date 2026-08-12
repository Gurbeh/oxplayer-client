import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_patch_playback_progress.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/refresh_after_watch_state.dart';

/// After playback ends, patch detail UserData immediately and refresh series/home.
///
/// [context.refreshData] after the player route often runs before [MediaControlWrapper.stop]
/// finishes its 1s delay and [playbackStopped] POST; listening for [playBackModel] → null
/// runs only after the server has been updated. Local patch uses the stop position already
/// known on [mediaPlaybackProvider] so the play button progress updates without a refetch race.
class OxplayerPlaybackDetailsRefresh extends ConsumerStatefulWidget {
  const OxplayerPlaybackDetailsRefresh({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<OxplayerPlaybackDetailsRefresh> createState() => _OxplayerPlaybackDetailsRefreshState();
}

class _OxplayerPlaybackDetailsRefreshState extends ConsumerState<OxplayerPlaybackDetailsRefresh> {
  ProviderSubscription<PlaybackModel?>? _playbackSub;

  @override
  void initState() {
    super.initState();
    if (!OxplayerConfig.isEnabled) return;
    _playbackSub = ref.listenManual<PlaybackModel?>(
      playBackModel,
      (previous, next) {
        if (previous == null || next != null) return;
        final item = previous.item;
        // Sync read: stop() clears playBackModel before zeroing mediaPlayback.position.
        final media = ref.read(mediaPlaybackProvider);
        final position = media.position;
        final duration = media.duration;

        oxPatchDetailProvidersPlaybackProgress(
          ref,
          item: item,
          position: position,
          runTime: duration,
        );

        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 200), () async {
            if (!mounted) return;
            await refreshAfterWatchStateChange(ref, item);
            if (!mounted) return;
            await oxRefreshHomeAfterPlayback(ref);
          }),
        );
      },
    );
  }

  @override
  void dispose() {
    _playbackSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
