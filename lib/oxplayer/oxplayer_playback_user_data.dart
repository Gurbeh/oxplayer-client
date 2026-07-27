import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/providers/video_player_provider.dart';

/// Keep [playBackModel] item userData in sync after mark watched / favorite from menus.
void oxplayerSyncPlaybackUserData(WidgetRef ref, String itemId, UserData? userData) {
  if (userData == null) return;
  final current = ref.read(playBackModel);
  if (current == null || current.item.id != itemId) return;
  ref.read(playBackModel.notifier).update((state) => state?.updateUserData(userData));
}

bool oxplayerIsActivePlaybackItem(WidgetRef ref, String itemId) {
  return ref.read(playBackModel)?.item.id == itemId;
}
