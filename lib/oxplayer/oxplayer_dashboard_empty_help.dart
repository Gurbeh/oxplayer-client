import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_help_content.dart';
import 'package:fladder/oxplayer/oxplayer_navigation_seerr.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';
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
class OxplayerDashboardEmptyHelpSliver extends ConsumerStatefulWidget {
  const OxplayerDashboardEmptyHelpSliver({
    required this.views,
    required this.dashboard,
    super.key,
  });

  final ViewsModel views;
  final HomeModel dashboard;

  @override
  ConsumerState<OxplayerDashboardEmptyHelpSliver> createState() =>
      _OxplayerDashboardEmptyHelpSliverState();
}

class _OxplayerDashboardEmptyHelpSliverState extends ConsumerState<OxplayerDashboardEmptyHelpSliver> {
  var _viewsHydrated = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(viewsProvider, (previous, next) {
      if (!_viewsHydrated && previous != next) {
        setState(() => _viewsHydrated = true);
      }
    });

    final showHelp = _viewsHydrated &&
        oxplayerIsHomeLibraryEmpty(views: widget.views, dashboard: widget.dashboard);

    if (!showHelp) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final seerrDiscover = OxplayerConfig.isEnabled &&
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FilledButton.icon(
                  onPressed: () => oxplayerNavigateToSeerr(context),
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(context.localized.oxplayerHomeEmptyLibraryDiscover),
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
