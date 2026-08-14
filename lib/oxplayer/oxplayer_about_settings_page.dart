import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_developer_mode_store.dart';
import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_version_tap_unlock.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/screens/shared/fladder_icon.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/application_info.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';

const _oxplayerWebsite = 'https://oxplayer.app';
const _oxplayerWebsiteLabel = 'oxplayer.app';

class OxplayerAboutSettingsPage extends ConsumerStatefulWidget {
  const OxplayerAboutSettingsPage({super.key});

  @override
  ConsumerState<OxplayerAboutSettingsPage> createState() => _OxplayerAboutSettingsPageState();
}

class _OxplayerAboutSettingsPageState extends ConsumerState<OxplayerAboutSettingsPage> {
  bool _developerModeUnlocked = false;
  OxplayerOxLoginKind? _loginKind;

  @override
  void initState() {
    super.initState();
    _loadDeveloperMode();
    _loadLoginKind();
  }

  Future<void> _loadLoginKind() async {
    final accountId = ref.read(userProvider)?.id;
    final controller = OxplayerTdlibBridgeController.instance();
    final hasBotToken = await controller.hasCachedBotToken();
    if (!mounted) return;
    final kind = await OxplayerOxLoginKindStore.resolve(
      accountId: accountId,
      tdlibUserSessionReady:
          controller.state.kind == OxTdlibAuthStateKind.ready && !controller.nativeSessionIsBot,
      hasBotToken: hasBotToken,
      nativeWaitingForUserAuth: controller.state.kind == OxTdlibAuthStateKind.waitingForPhoneNumber ||
          controller.state.kind == OxTdlibAuthStateKind.failed,
    );
    if (!mounted) return;
    setState(() => _loginKind = kind);
  }

  Future<void> _loadDeveloperMode() async {
    final unlocked = await OxplayerDeveloperModeStore.isUnlocked();
    if (!mounted) return;
    setState(() => _developerModeUnlocked = unlocked);
  }

  Future<void> _unlockDeveloperMode() async {
    if (_developerModeUnlocked) return;
    await OxplayerDeveloperModeStore.unlock();
    if (!mounted) return;
    setState(() => _developerModeUnlocked = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.localized.oxplayerDeveloperModeUnlocked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final applicationInfo = ref.watch(applicationInfoProvider);

    return SettingsScaffold(
      label: '',
      items: [
        const FladderLogo(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            OxplayerVersionTapUnlock(
              onUnlocked: _unlockDeveloperMode,
              child: Text(context.localized.aboutVersion(applicationInfo.versionAndPlatform)),
            ),
            Text(context.localized.aboutBuild(applicationInfo.buildNumber)),
            if (_loginKind != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  switch (_loginKind!) {
                    OxplayerOxLoginKind.session => context.localized.oxplayerAboutLoginSession,
                    OxplayerOxLoginKind.bot => context.localized.oxplayerAboutLoginBot,
                  },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(12),
                minimumSize: const Size(64, 64),
              ),
              onPressed: () => launchUrl(context, _oxplayerWebsite),
              icon: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(IconsaxPlusLinear.global),
                  Text(
                    _oxplayerWebsiteLabel,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
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
        if (_developerModeUnlocked)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.tonal(
                onPressed: () => context.router.push(const OxplayerDeveloperModeRoute()),
                child: Text(context.localized.oxplayerDeveloperModeTitle),
              ),
            ],
          ),
      ].addInBetween(const SizedBox(height: 16)),
    );
  }
}
