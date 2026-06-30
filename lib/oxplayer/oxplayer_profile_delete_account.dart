import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_account_delete_api.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_navigation.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';
import 'package:fladder/util/localization_helper.dart';

/// OX-only profile section: delete server account (Settings → Profile).
List<Widget> oxplayerProfileDeleteAccountGroup(BuildContext context, WidgetRef ref) {
  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.oxplayerDeleteAccountSection),
    [
      SettingsListTile(
        label: Text(
          context.localized.oxplayerDeleteAccountTitle,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        subLabel: Text(context.localized.oxplayerDeleteAccountSubtitle),
        onTap: () => _confirmDeleteAccount(context, ref),
      ),
    ],
  );
}

Future<void> _confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final loc = context.localized;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.oxplayerDeleteAccountDialogTitle),
      content: Text(loc.oxplayerDeleteAccountDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(loc.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(loc.oxplayerDeleteAccountConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final account = ref.read(userProvider);
  final token = account?.credentials.token;
  if (account == null || token == null || token.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.oxplayerDeleteAccountFailed)),
    );
    return;
  }

  try {
    await OxplayerAccountDeleteApi().deleteAccount(accessToken: token);
  } on OxplayerAccountDeleteException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.oxplayerDeleteAccountFailed)),
    );
    return;
  }

  await ref.read(authProvider.notifier).logOutUser();
  if (!context.mounted) return;
  await context.router.replaceAll(oxplayerSignOutRouteList());
  await ref.read(authProvider.notifier).initModel();
}

/// Opens the main-bot delete-account deep link (privacy policy fallback).
Future<void> oxplayerOpenBotDeleteAccountLink() async {
  final link = OxplayerEnv.telegramBotDeleteAccountLink;
  if (link == null) return;
  final uri = Uri.parse(link);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
