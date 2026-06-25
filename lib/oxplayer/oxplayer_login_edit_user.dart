import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';

/// OX account editor — no Jellyfin server URL/name (single shared API).
class OxplayerLoginEditUser extends ConsumerWidget {
  final AccountModel user;

  const OxplayerLoginEditUser({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Center(child: Text(user.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Row(
            children: [
              Icon(user.authMethod.icon),
              const SizedBox(width: 8),
              Text(user.authMethod.name(context)),
            ],
          ),
          Row(
            children: [
              const Icon(IconsaxPlusBold.clock),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat.yMMMEd(context.localized.localeName).format(user.lastUsed)),
                  Text(DateFormat.Hms(context.localized.localeName).format(user.lastUsed)),
                ],
              ),
            ],
          ),
          const Divider(),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () async {
                await ref.read(sharedUtilityProvider).removeAccount(user);
                ref.read(authProvider.notifier).getSavedAccounts();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.remove_rounded),
              label: const Text('Remove user'),
            ),
          ),
        ].addPadding(const EdgeInsets.symmetric(vertical: 8)),
      ),
    );
  }
}
