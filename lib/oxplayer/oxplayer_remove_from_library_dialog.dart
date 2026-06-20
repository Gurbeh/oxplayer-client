import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/api_result.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/filled_button_await.dart';

/// OXPlayer override for the delete dialog.
/// Shows "Remove from library" copy instead of Jellyfin's "delete from filesystem" wording,
/// because DELETE /Items/{id} on OXPlayer only removes the item from the user's personal library.
Future<ApiResult<dynamic>?> oxplayerShowRemoveFromLibraryDialog(
  BuildContext context,
  ItemBaseModel item,
  WidgetRef ref,
) async {
  Response<dynamic>? response;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Remove ${item.type.label(context.localized)} from library'),
      content: Text(
        '"${item.name}" will be removed from your library.',
      ),
      scrollable: true,
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.localized.cancel),
        ),
        FilledButtonAwait(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            iconColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: () async {
            response = await ref.read(jellyApiProvider).deleteItem(item.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return response?.apiResult;
}
