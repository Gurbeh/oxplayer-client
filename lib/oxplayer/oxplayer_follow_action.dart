import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/providers/ox_catalog_follow.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

const _followLabel = 'دنبال کردن';
const _unfollowLabel = 'لغو دنبال کردن';

bool oxIsFollowableItem(ItemBaseModel item) {
  return item is SeriesModel || item is MovieModel;
}

List<ItemAction> oxplayerFollowActions(BuildContext context, WidgetRef ref, ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled || !oxIsFollowableItem(item)) return const [];

  final followAsync = ref.watch(oxCatalogFollowStatusProvider(item.id));
  final following = followAsync.value ?? false;

  return [
    ItemActionButton(
      icon: Icon(following ? IconsaxPlusLinear.notification_bing : IconsaxPlusLinear.notification),
      label: Text(following ? _unfollowLabel : _followLabel),
      action: () => _toggleFollow(context, ref, item.id),
    ),
  ];
}

Future<void> _toggleFollow(BuildContext context, WidgetRef ref, String catalogId) async {
  final notifier = ref.read(oxCatalogFollowStatusProvider(catalogId).notifier);
  final wasFollowing = ref.read(oxCatalogFollowStatusProvider(catalogId)).value ?? false;
  await notifier.toggle();
  if (!context.mounted) return;
  final nowFollowing = ref.read(oxCatalogFollowStatusProvider(catalogId)).value ?? false;
  if (nowFollowing == wasFollowing) return;
  FladderSnack.show(
    nowFollowing ? 'سریال/فیلم به دنبال‌شده‌ها اضافه شد' : 'از دنبال‌شده‌ها حذف شد',
    context: context,
  );
}
