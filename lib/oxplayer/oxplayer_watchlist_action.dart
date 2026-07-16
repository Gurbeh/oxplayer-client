import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_follow_action.dart';
import 'package:fladder/oxplayer/providers/ox_item_flags.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

List<ItemAction> oxplayerWatchlistActions(BuildContext context, WidgetRef ref, ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled || !oxIsFollowableItem(item)) return const [];

  final watchlisted = ref.watch(oxItemFlagsProvider.select((s) => s.isWatchlisted(item.id)));

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
  final loc = context.localized;
  final wasWatchlisted = ref.read(oxItemFlagsProvider).isWatchlisted(catalogId);
  final ok = await ref.read(oxItemFlagsProvider.notifier).toggleWatchlisted(catalogId);
  if (!ok) {
    FladderSnack.show(loc.oxplayerWatchlistFailed);
    return;
  }
  unawaited(ref.read(viewsProvider.notifier).fetchViews());
  FladderSnack.show(!wasWatchlisted ? loc.oxplayerWatchlistAdded : loc.oxplayerWatchlistRemoved);
}
