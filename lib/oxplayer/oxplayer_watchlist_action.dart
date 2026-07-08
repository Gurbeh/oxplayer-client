import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_follow_action.dart';
import 'package:fladder/oxplayer/providers/ox_catalog_interest.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

List<ItemAction> oxplayerWatchlistActions(BuildContext context, WidgetRef ref, ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled || !oxIsFollowableItem(item)) return const [];

  final interestAsync = ref.watch(oxCatalogInterestProvider(item.id));
  final watchlisted = interestAsync.value?.watchlisted ?? false;

  return [
    ItemActionButton(
      selected: watchlisted,
      icon: Icon(watchlisted ? IconsaxPlusBold.bookmark : IconsaxPlusLinear.bookmark),
      label: Text(watchlisted ? context.localized.oxplayerUnwatchlist : context.localized.oxplayerWatchlist),
      action: () => _toggleWatchlist(context, ref, item.id),
    ),
  ];
}

Future<void> _toggleWatchlist(BuildContext context, WidgetRef ref, String catalogId) async {
  final wasWatchlisted = (await ref.read(oxCatalogInterestProvider(catalogId).future)).watchlisted;
  final ok = await ref.read(oxCatalogInterestProvider(catalogId).notifier).toggleWatchlisted();
  if (!context.mounted) return;
  if (!ok) {
    FladderSnack.show(context.localized.oxplayerWatchlistFailed, context: context);
    return;
  }
  final nowWatchlisted = ref.read(oxCatalogInterestProvider(catalogId)).value?.watchlisted ?? false;
  if (nowWatchlisted == wasWatchlisted) return;
  FladderSnack.show(
    nowWatchlisted ? context.localized.oxplayerWatchlistAdded : context.localized.oxplayerWatchlistRemoved,
    context: context,
  );
}
