import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dashboard_skeleton.dart';
import 'package:fladder/oxplayer/oxplayer_help_content.dart';
import 'package:fladder/oxplayer/oxplayer_navigation_seerr.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';

bool oxplayerIsHomeLibraryEmpty({
  required ViewsModel views,
  required HomeModel dashboard,
}) {
  final allResume = [
    ...dashboard.resumeVideo,
    ...dashboard.resumeAudio,
    ...dashboard.resumeBooks,
  ];

  if (dashboard.activePrograms.isNotEmpty) return false;
  if (allResume.isNotEmpty) return false;
  if (dashboard.nextUp.isNotEmpty) return false;

  final hasRecentlyAdded = views.dashboardViews.any(
    (view) => view.collectionType != CollectionType.livetv && view.recentlyAdded.isNotEmpty,
  );
  if (hasRecentlyAdded) return false;

  return true;
}

/// Shows [OxplayerHelpContent] on Home when the user's library has no items yet.
class OxplayerDashboardEmptyHelpSliver extends ConsumerWidget {
  const OxplayerDashboardEmptyHelpSliver({
    required this.views,
    required this.dashboard,
    super.key,
  });

  final ViewsModel views;
  final HomeModel dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerConfig.isEnabled) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final dataReady = oxHomeDashboardDataReady(views: views, dashboard: dashboard);
    final showHelp = dataReady && oxplayerIsHomeLibraryEmpty(views: views, dashboard: dashboard);

    if (!showHelp) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final seerrDiscover =
        ref.watch(userProvider.select((u) => u?.seerrCredentials?.isConfigured == true));

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 24,
          bottom: 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                seerrDiscover
                    ? context.localized.oxplayerHomeEmptyLibraryTitle
                    : context.localized.oxplayerHomeWelcome,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (seerrDiscover) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  context.localized.oxplayerHomeEmptyLibraryBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: _EmptyLibraryDiscoverButton(
                  label: context.localized.oxplayerHomeEmptyLibraryDiscover,
                  onTap: () => oxplayerNavigateToSeerr(context),
                ),
              ),
            ] else
              const OxplayerHelpContent(embedded: true),
          ],
        ),
      ),
    );
  }
}

/// TV-friendly discover CTA — [FocusButton] handles d-pad select/enter keys.
class _EmptyLibraryDiscoverButton extends StatelessWidget {
  const _EmptyLibraryDiscoverButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(20);
    final isDpad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    return FocusButton(
      onTap: onTap,
      autoFocus: isDpad,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: radius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, color: theme.colorScheme.onPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
