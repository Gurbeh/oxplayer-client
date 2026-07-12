import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_dashboard_skeleton.dart';
import 'package:fladder/oxplayer/providers/ox_watchlist_dashboard.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/localization_helper.dart';

Iterable<Widget> oxplayerDashboardRecentlyAddedRows({
  required BuildContext context,
  required WidgetRef ref,
  required ViewsModel views,
  required EdgeInsets padding,
  required bool useTVExpandedLayout,
  required Iterable<Widget> defaultRows,
}) {
  if (!OxplayerConfig.isEnabled) return defaultRows;

  final rows = <Widget>[];
  var insertedWatchLater = false;

  for (final view in views.dashboardViews.where(
    (element) => element.recentlyAdded.isNotEmpty && element.collectionType != CollectionType.livetv,
  )) {
    rows.add(
      PosterRow(
        tvMode: useTVExpandedLayout,
        contentPadding: padding,
        label: context.localized.dashboardRecentlyAdded(view.name),
        collectionAspectRatio: view.collectionType.aspectRatio,
        onLabelClick: () {
          if (view.collectionType == CollectionType.livetv) {
            return LiveTvRoute().navigate(context);
          }
          return context.router.push(
            LibrarySearchRoute(
              viewModelId: view.id,
              types: switch (view.collectionType) {
                CollectionType.tvshows => {
                    FladderItemType.episode: true,
                  },
                _ => {},
              },
              sortingOptions: switch (view.collectionType) {
                CollectionType.books ||
                CollectionType.boxsets ||
                CollectionType.folders ||
                CollectionType.music =>
                  SortingOptions.dateLastContentAdded,
                _ => SortingOptions.dateAdded,
              },
              sortOrder: SortingOrder.descending,
              recursive: true,
            ),
          );
        },
        posters: view.recentlyAdded,
      ),
    );

    if (!insertedWatchLater && view.collectionType == CollectionType.tvshows) {
      rows.add(
        OxplayerWatchLaterPosterRow(
          contentPadding: padding,
          tvMode: useTVExpandedLayout,
          views: views,
        ),
      );
      insertedWatchLater = true;
    }
  }

  if (!insertedWatchLater) {
    rows.add(
      OxplayerWatchLaterPosterRow(
        contentPadding: padding,
        tvMode: useTVExpandedLayout,
        views: views,
      ),
    );
  }

  return rows;
}

class OxplayerWatchLaterPosterRow extends ConsumerWidget {
  const OxplayerWatchLaterPosterRow({
    required this.contentPadding,
    required this.tvMode,
    required this.views,
    super.key,
  });

  final EdgeInsets contentPadding;
  final bool tvMode;
  final ViewsModel views;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerConfig.isEnabled) return const SizedBox.shrink();

    if (ref.watch(oxWatchlistFeedHandledProvider)) {
      final data = ref.watch(oxWatchlistDashboardFeedProvider) ?? OxWatchlistDashboardData.empty;
      if (data.items.isEmpty) return const SizedBox.shrink();
      final playlistsView = views.dashboardViews.firstWhereOrNull(
        (view) => view.collectionType == CollectionType.playlists,
      );
      return PosterRow(
        tvMode: tvMode,
        contentPadding: contentPadding,
        label: context.localized.oxplayerWatchlist,
        onLabelClick: data.playlistId == null || playlistsView == null
            ? null
            : () {
                context.router.push(
                  LibrarySearchRoute(
                    viewModelId: playlistsView.id,
                    folderId: [data.playlistId!],
                  ),
                );
              },
        posters: data.items,
      );
    }

    final cachedFeed = ref.watch(oxWatchlistDashboardFeedProvider);
    if (cachedFeed != null && cachedFeed.items.isNotEmpty) {
      final playlistsView = views.dashboardViews.firstWhereOrNull(
        (view) => view.collectionType == CollectionType.playlists,
      );
      return PosterRow(
        tvMode: tvMode,
        contentPadding: contentPadding,
        label: context.localized.oxplayerWatchlist,
        onLabelClick: cachedFeed.playlistId == null || playlistsView == null
            ? null
            : () {
                context.router.push(
                  LibrarySearchRoute(
                    viewModelId: playlistsView.id,
                    folderId: [cachedFeed.playlistId!],
                  ),
                );
              },
        posters: cachedFeed.items,
      );
    }

    final watchlistAsync = ref.watch(oxWatchlistDashboardProvider);
    return watchlistAsync.when(
      data: (data) {
        if (data.items.isEmpty) return const SizedBox.shrink();
        final playlistsView = views.dashboardViews.firstWhereOrNull(
          (view) => view.collectionType == CollectionType.playlists,
        );
        return PosterRow(
          tvMode: tvMode,
          contentPadding: contentPadding,
          label: context.localized.oxplayerWatchlist,
          onLabelClick: data.playlistId == null || playlistsView == null
              ? null
              : () {
                  context.router.push(
                    LibrarySearchRoute(
                      viewModelId: playlistsView.id,
                      folderId: [data.playlistId!],
                    ),
                  );
                },
          posters: data.items,
        );
      },
      loading: () => OxPosterRowSkeleton(contentPadding: contentPadding),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
