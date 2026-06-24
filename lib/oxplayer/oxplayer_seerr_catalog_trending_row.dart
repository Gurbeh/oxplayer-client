import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_seerr_catalog_trending.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/util/localization_helper.dart';

/// First Seerr dashboard row: trending TMDB titles available in the OX catalog.
class OxplayerSeerrCatalogTrendingRow extends ConsumerWidget {
  const OxplayerSeerrCatalogTrendingRow({
    required this.contentPadding,
    super.key,
  });

  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerEnv.isEnabled) {
      return const SizedBox.shrink();
    }

    final asyncPosters = ref.watch(oxSeerrCatalogTrendingProvider);
    return asyncPosters.when(
      data: (posters) {
        if (posters.isEmpty) {
          return const SizedBox.shrink();
        }
        return SeerrPosterRow(
          label: context.localized.oxplayerSeerrCatalogTrending,
          posters: posters,
          contentPadding: contentPadding,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
