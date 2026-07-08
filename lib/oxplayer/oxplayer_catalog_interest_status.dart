import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_follow_action.dart';
import 'package:fladder/oxplayer/providers/ox_catalog_interest.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

/// One HTTP round-trip before opening a poster context menu (follow + watch-later).
Future<void> oxPrefetchCatalogInterestStatus(WidgetRef ref, ItemBaseModel item) async {
  if (!OxplayerConfig.isEnabled || !oxIsFollowableItem(item)) return;
  await ref.read(oxCatalogInterestProvider(item.id).future);
}

/// Bottom-sheet action list that rebuilds when catalog interest resolves.
Widget oxReactivePosterActionsList({
  required BuildContext context,
  required WidgetRef ref,
  required ItemBaseModel poster,
  ScrollController? scrollController,
  Set<ItemActions> excludeActions = const {},
  List<ItemAction> otherActions = const [],
  Function(UserData? newData)? onUserDataChanged,
  Function(ItemBaseModel item)? onItemUpdated,
  Function(ItemBaseModel item)? onDeleteSuccesFully,
}) {
  return Consumer(
    builder: (context, ref, _) {
      return ListView(
        shrinkWrap: true,
        controller: scrollController,
        children: poster
            .generateActions(
              context,
              ref,
              exclude: excludeActions,
              otherActions: otherActions,
              onUserDataChanged: onUserDataChanged,
              onDeleteSuccesFully: onDeleteSuccesFully,
              onItemUpdated: onItemUpdated,
            )
            .listTileItems(context, useIcons: true),
      );
    },
  );
}
