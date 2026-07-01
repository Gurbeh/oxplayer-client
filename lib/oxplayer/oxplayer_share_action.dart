import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_share.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

List<ItemAction> oxplayerShareActions(BuildContext context, ItemBaseModel item) {
  if (!oxIsShareableItem(item)) return const [];

  return [
    ItemActionButton(
      icon: const Icon(IconsaxPlusLinear.share),
      label: Text(context.localized.share),
      action: () => oxplayerShareItem(context, item),
    ),
  ];
}

Future<void> oxplayerShareItem(BuildContext context, ItemBaseModel item) async {
  if (!oxIsShareableItem(item)) return;
  final url = oxplayerBuildShareUrl(
    item.id,
    mediaSourceId: oxplayerShareMediaSourceIdFromItem(item),
  );
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) {
    FladderSnack.show(context.localized.shareLinkCopied, context: context);
  }
  await SharePlus.instance.share(ShareParams(text: url, subject: item.name));
}
