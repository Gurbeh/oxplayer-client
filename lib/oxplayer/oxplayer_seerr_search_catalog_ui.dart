import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_catalog.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/button_group.dart';

/// When true, Seerr search queries the Jellyfin catalog instead of TMDB-only subset.
final oxplayerSeerrCatalogOnlyFilterProvider = StateProvider<bool>((ref) => false);

class OxplayerSeerrCatalogFilterChip extends ConsumerWidget {
  const OxplayerSeerrCatalogFilterChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogOnly = ref.watch(oxplayerSeerrCatalogOnlyFilterProvider);
    return ExpressiveButton(
      isSelected: catalogOnly,
      icon: catalogOnly ? const Icon(Icons.video_library) : null,
      label: Text(context.localized.library(1)),
      onPressed: () {
        ref.read(oxplayerSeerrCatalogOnlyFilterProvider.notifier).state = !catalogOnly;
      },
    );
  }
}

class OxplayerSeerrSearchCatalogRow extends ConsumerWidget {
  final List<SeerrDashboardPosterModel>? inCatalog;
  final List<SeerrDashboardPosterModel> results;
  final String query;

  const OxplayerSeerrSearchCatalogRow({
    this.inCatalog,
    required this.results,
    required this.query,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogOnly = ref.watch(oxplayerSeerrCatalogOnlyFilterProvider);
    if (catalogOnly || query.trim().isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final catalogHits = inCatalog ?? oxplayerPartitionSeerrSearchResults(results).inCatalog;
    if (catalogHits.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: 16,
          left: AdaptiveLayout.adaptivePadding(context).left,
          right: AdaptiveLayout.adaptivePadding(context).right,
        ),
        child: SeerrPosterRow(
          posters: catalogHits,
          label: context.localized.library(1),
        ),
      ),
    );
  }
}
