import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/ox_series_details_loader.dart';
import 'package:fladder/oxplayer/ox_staged_detail_load.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

final seriesDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeriesDetailViewNotifier, SeriesModel?, String>((ref, id) {
  return SeriesDetailViewNotifier(ref);
});

class SeriesDetailViewNotifier extends StateNotifier<SeriesModel?> {
  SeriesDetailViewNotifier(this.ref) : super(null);

  final Ref ref;
  int _loadGeneration = 0;

  Future<Response?> fetchDetails(ItemBaseModel seriesModel) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(SeriesModel? next) {
          if (loadGen != _loadGeneration) return;
          state = next;
        }

        if (seriesModel is SeriesModel) {
          apply(state ?? seriesModel);
        }

        if (OxplayerConfig.isEnabled) {
          final catalogPrefetch = oxFetchSeriesCatalogBySeason(
            ref.read(jellyApiProvider),
            seriesModel.id,
          );
          final core = await oxFetchSeriesCoreState(ref, seriesModel, state);
          if (core == null) return null;
          apply(core);

          if (oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(seriesModel.id)))) {
            oxPrefetchSeerrTvRatings(ref, seriesModel.id, core.tmdbId);
          }

          unawaited(_oxContinueSeriesLoad(seriesModel.id, loadGen, catalogPrefetch));
          return null;
        }

        final newState = await oxFetchSeriesCoreState(ref, seriesModel, state);
        if (newState == null) return null;
        apply(newState);

        if (OxplayerEnv.isEnabled &&
            oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(seriesModel.id)))) {
          oxPrefetchSeerrTvRatings(ref, seriesModel.id, newState.tmdbId);
        }

        final withCatalog = await oxLoadSeriesCatalogPhase(ref, newState, seriesModel.id);
        apply(withCatalog);

        final supplementary = await oxLoadSeriesSupplementaryPhase(ref, seriesModel.id, withCatalog);
        apply(
          oxMergeSeriesSupplementary(
            withCatalog,
            related: supplementary.related,
            seerrRelated: supplementary.seerrRelated,
            seerrRecommended: supplementary.seerrRecommended,
            seerrUrl: supplementary.seerrUrl,
            specialFeatures: supplementary.specialFeatures,
          ),
        );
        return null;
      } catch (e) {
        log("Error fetching series details: $e");
        return null;
      }
    }

    if (OxplayerConfig.isEnabled) {
      return OxplayerScreenTelemetry.trackLoad(
        screen: 'series_detail',
        phase: 'fetch',
        load: load,
      );
    }
    return load();
  }

  Future<void> _oxContinueSeriesLoad(
    String seriesId,
    int loadGen,
    Future<OxSeriesCatalogLoad> catalogPrefetch,
  ) async {
    try {
      final base = state;
      if (base == null || loadGen != _loadGeneration) return;

      final supplementaryFuture = oxLoadSeriesSupplementaryPhase(ref, seriesId, base);
      final withCatalog = await oxLoadSeriesCatalogPhase(
        ref,
        base,
        seriesId,
        prefetchCatalog: catalogPrefetch,
      );
      if (loadGen != _loadGeneration) return;
      state = withCatalog;

      final supplementary = await supplementaryFuture;
      if (loadGen != _loadGeneration) return;
      state = oxMergeSeriesSupplementary(
        withCatalog,
        related: supplementary.related,
        seerrRelated: supplementary.seerrRelated,
        seerrRecommended: supplementary.seerrRecommended,
        seerrUrl: supplementary.seerrUrl,
        specialFeatures: supplementary.specialFeatures,
      );
    } catch (e) {
      log("Error loading staged series details: $e");
    }
  }

  void updateEpisodeInfo(EpisodeModel episode) {
    final index = state?.availableEpisodes?.indexWhere((e) => e.id == episode.id);

    final newList = state?.availableEpisodes?.toList() ?? [];
    newList[index ?? 0] = episode;

    if (index != null) {
      state = state?.copyWith(
        availableEpisodes: newList,
      );
    }
  }

  void setCurrentEpisode(EpisodeModel? episodeModel) {
    state = state?.copyWith(selectedEpisode: episodeModel);
  }
}
