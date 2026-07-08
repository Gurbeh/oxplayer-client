import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/providers/ox_catalog_interest.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

bool oxIsFollowableItem(ItemBaseModel item) {
  return item is SeriesModel || item is MovieModel;
}

List<ItemAction> oxplayerFollowActions(BuildContext context, WidgetRef ref, ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled || !oxIsFollowableItem(item)) return const [];

  final interestAsync = ref.watch(oxCatalogInterestProvider(item.id));
  final following = interestAsync.value?.following ?? false;

  return [
    ItemActionButton(
      selected: following,
      icon: Icon(following ? IconsaxPlusLinear.notification_bing : IconsaxPlusLinear.notification),
      label: Text(following ? context.localized.oxplayerUnfollow : context.localized.oxplayerFollow),
      action: () => _toggleFollow(context, ref, item.id),
    ),
  ];
}

Future<void> _toggleFollow(BuildContext context, WidgetRef ref, String catalogId) async {
  final wasFollowing = (await ref.read(oxCatalogInterestProvider(catalogId).future)).following;
  final ok = await ref.read(oxCatalogInterestProvider(catalogId).notifier).toggleFollowing();
  if (!context.mounted) return;
  if (!ok) {
    FladderSnack.show(context.localized.oxplayerFollowFailed, context: context);
    return;
  }
  final nowFollowing = ref.read(oxCatalogInterestProvider(catalogId)).value?.following ?? false;
  if (nowFollowing == wasFollowing) return;
  FladderSnack.show(
    nowFollowing ? context.localized.oxplayerFollowAdded : context.localized.oxplayerFollowRemoved,
    context: context,
  );
}
