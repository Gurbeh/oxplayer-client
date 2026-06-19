import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_about_error_logs_button.dart';
import 'package:fladder/screens/crash_screen/crash_screen.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/screens/settings/widgets/settings_update_information.dart';
import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';

const _oxplayerWebsite = 'https://oxplayer.app';
const _oxplayerWebsiteLabel = 'oxplayer.app';

class OxplayerAboutSettingsPage extends ConsumerWidget {
  const OxplayerAboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applicationInfo = ref.watch(applicationInfoProvider);

    return SettingsScaffold(
      label: '',
      items: [
        const FladderLogo(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(context.localized.aboutVersion(applicationInfo.versionAndPlatform)),
            Text(context.localized.aboutBuild(applicationInfo.buildNumber)),
            const SizedBox(height: 16),
            const Text('Created by Gurbeh'),
          ],
        ),
        const FractionallySizedBox(
          widthFactor: 0.25,
          child: Divider(
            indent: 16,
            endIndent: 16,
          ),
        ),
        SizedBox(
          width: 100,
          child: IconButton.filledTonal(
            onPressed: () => launchUrl(context, _oxplayerWebsite),
            icon: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(IconsaxPlusLinear.global),
                Text(_oxplayerWebsiteLabel),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: () => showLicensePage(
                context: context,
                applicationIcon: const FladderIcon(size: 55),
                applicationVersion: applicationInfo.versionPlatformBuild,
                applicationLegalese: 'Gurbeh',
                useRootNavigator: true,
              ),
              child: Text(context.localized.aboutLicenses),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OxplayerAboutErrorLogsButton(
              label: context.localized.errorLogs,
              onOpenErrorLogs: () => showDialog(
                context: context,
                builder: (context) => const CrashScreen(),
              ),
            ),
          ],
        ),
        const SettingsUpdateInformation(),
      ].addInBetween(const SizedBox(height: 16)),
    );
  }
}
