import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_series_details_loader.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/dashboard_provider.dart';

/// After Home paints: warm detail SWR for slider + first posters of each shelf.
///
/// Cheap path: `GET /Items/{id}` (Play for movies / episode MediaSources).
/// Series catalog only for slider targets (Seasons+Episodes is heavier).
abstract final class OxplayerHomeDetailPrefetch {
  static const shelfTake = 5;
  static const concurrency = 3;
  static const _startDelay = Duration(milliseconds: 500);

  static int _generation = 0;

  /// Fire-and-forget; newer [schedule] cancels older work via generation.
  ///
  /// [dashboardViews] must be a snapshot — never read [viewsProvider] from
  /// inside [viewsProvider] (Riverpod self-dependency).
  static void schedule(Ref ref, {required List<ViewModel> dashboardViews}) {
    if (!OxplayerConfig.isEnabled) return;
    final gen = ++_generation;
    unawaited(_run(ref, gen, dashboardViews: dashboardViews));
  }

  static Future<void> _run(
    Ref ref,
    int gen, {
    required List<ViewModel> dashboardViews,
  }) async {
    await Future<void>.delayed(_startDelay);
    if (gen != _generation) return;

    final targets = _collect(ref, dashboardViews: dashboardViews);
    if (targets.isEmpty) return;

    final queue = List<_PrefetchTarget>.from(targets);
    final workers = List.generate(
      concurrency.clamp(1, queue.length),
      (_) => _worker(ref, queue, gen),
    );
    await Future.wait(workers);
  }

  static Future<void> _worker(Ref ref, List<_PrefetchTarget> queue, int gen) async {
    while (queue.isNotEmpty) {
      if (gen != _generation) return;
      final next = queue.removeAt(0);
      try {
        await _prefetchOne(ref, next);
      } catch (_) {
        // Best-effort; home UI already painted.
      }
    }
  }

  static Future<void> _prefetchOne(Ref ref, _PrefetchTarget target) async {
    final cached = await oxLoadCachedLibraryItemJson(ref, target.itemId);
    if (cached == null) {
      await oxFetchLibraryItemJson(ref, target.itemId);
    }

    final seriesId = target.seriesCatalogId;
    if (seriesId == null || seriesId.isEmpty) return;

    // Chopper SWR: instant no-op when seasons/episodes already on disk.
    final api = ref.read(jellyApiProvider);
    await oxFetchSeriesCatalogBySeason(api, seriesId);
  }

  static List<_PrefetchTarget> _collect(
    Ref ref, {
    required List<ViewModel> dashboardViews,
  }) {
    final dashboard = ref.read(dashboardProvider);
    final seen = <String>{};
    final out = <_PrefetchTarget>[];

    void add(ItemBaseModel item, {required bool wantSeriesCatalog}) {
      if (item.id.isEmpty || !seen.add(item.id)) return;
      String? seriesCatalogId;
      if (wantSeriesCatalog) {
        seriesCatalogId = switch (item) {
          SeriesModel _ => item.id,
          EpisodeModel e => e.parentId,
          _ => null,
        };
        if (seriesCatalogId != null && seriesCatalogId.isEmpty) {
          seriesCatalogId = null;
        }
      }
      out.add(_PrefetchTarget(itemId: item.id, seriesCatalogId: seriesCatalogId));
    }

    // Slider / rails — highest tap chance.
    for (final item in [...dashboard.nextUp, ...dashboard.resumeVideo]) {
      add(item, wantSeriesCatalog: true);
    }

    // First posters of each home shelf.
    for (final view in dashboardViews) {
      for (final item in view.recentlyAdded.take(shelfTake)) {
        add(item, wantSeriesCatalog: false);
      }
    }

    return out;
  }
}

class _PrefetchTarget {
  const _PrefetchTarget({required this.itemId, this.seriesCatalogId});

  final String itemId;
  final String? seriesCatalogId;
}
