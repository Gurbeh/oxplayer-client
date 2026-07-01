import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';

/// Fladder [PlaybackModelHelper.loadNewVideo] reuses [oldModel.playbackQueue] without
/// updating [PlaybackQueueState.mainQueueCurrentId], so after auto-next from ep1→ep2
/// the "next episode" anchor stays on ep1 and suggests ep2 again.
class OxPlaybackModelHelper extends PlaybackModelHelper {
  const OxPlaybackModelHelper({required super.ref});

  PlaybackModel? _withQueueAnchor(PlaybackModel? model, String itemId) {
    if (model == null) return null;
    return model.updatePlaybackQueue(model.playbackQueue.jumpToItem(itemId));
  }

  @override
  Future<PlaybackModel?> loadNewVideo(ItemBaseModel newItem) async {
    ref.read(videoPlayerProvider).pause();
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: true));
    final currentModel = ref.read(playBackModel);
    final patchedOld = _withQueueAnchor(currentModel, newItem.id);
    final newModel = await createPlaybackModel(
      null,
      newItem,
      oldModel: patchedOld,
    );
    if (newModel == null) return null;
    ref.read(videoPlayerProvider.notifier).loadPlaybackItem(newModel, Duration.zero);
    return newModel;
  }
}

final oxPlaybackModelHelper = Provider<PlaybackModelHelper>((ref) {
  return OxPlaybackModelHelper(ref: ref);
});
