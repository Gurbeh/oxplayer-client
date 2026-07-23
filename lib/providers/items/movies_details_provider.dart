import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_staged_detail_load.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_media_variant.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

part 'movies_details_provider.g.dart';

@riverpod
class MovieDetails extends _$MovieDetails {
  int _loadGeneration = 0;

  late final JellyService api = ref.read(jellyApiProvider);

  @override
  MovieModel? build(String arg) => null;

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    Future<Response?> load() async {
      try {
        final loadGen = ++_loadGeneration;
        void apply(MovieModel? next) {
          if (loadGen != _loadGeneration) return;
          state = next;
        }

        if (item is MovieModel) {
          apply(state ?? item);
        }

        if (OxplayerConfig.isEnabled) {
          // Disk SWR: MediaSources → Play button before network round-trip.
          final cached = await oxLoadCachedLibraryItemDetails(ref, item.id);
          if (cached != null && cached.model is MovieModel) {
            final cachedMovie = (cached.model as MovieModel).copyWith(
              related: state?.related ?? const [],
              seerrRelated: state?.seerrRelated ?? const [],
              seerrRecommended: state?.seerrRecommended ?? const [],
              specialFeatures: state?.specialFeatures ?? const [],
            );
            apply(oxplayerPrepareMovieMediaStreams(cachedMovie, ref) ?? cachedMovie);
          }

          final core = await oxFetchMovieCoreState(ref, item, state);
          if (core == null) return null;
          var playable = oxplayerPrepareMovieMediaStreams(core, ref) ?? core;
          apply(playable);

          oxPrefetchMovieSeerrRatings(ref, item.id, core.tmdbId);

          unawaited(_oxContinueMovieLoad(item.id, loadGen));
          return null;
        }

        final newState = await oxFetchMovieCoreState(ref, item, state);
        if (newState == null) return null;
        apply(newState);

        oxPrefetchMovieSeerrRatings(ref, item.id, newState.tmdbId);

        final supplementary = await oxLoadMovieSupplementaryPhase(ref, item.id, newState);
        var merged = oxMergeMovieSupplementary(
          newState,
          related: supplementary.related,
          seerrRelated: supplementary.seerrRelated,
          seerrRecommended: supplementary.seerrRecommended,
          seerrUrl: supplementary.seerrUrl,
          specialFeatures: supplementary.specialFeatures,
        );
        if (OxplayerConfig.isEnabled) {
          merged = oxplayerPrepareMovieMediaStreams(merged, ref) ?? merged;
        }
        apply(merged);
        return null;
      } catch (e) {
        return null;
      }
    }

    if (OxplayerConfig.isEnabled) {
      return OxplayerScreenTelemetry.trackLoad(
        screen: 'movie_detail',
        phase: 'fetch',
        load: load,
      );
    }
    return load();
  }

  Future<void> _oxContinueMovieLoad(String itemId, int loadGen) async {
    try {
      final base = state;
      if (base == null || loadGen != _loadGeneration) return;

      final supplementary = await oxLoadMovieSupplementaryPhase(ref, itemId, base);
      if (loadGen != _loadGeneration) return;

      var merged = oxMergeMovieSupplementary(
        base,
        related: supplementary.related,
        seerrRelated: supplementary.seerrRelated,
        seerrRecommended: supplementary.seerrRecommended,
        seerrUrl: supplementary.seerrUrl,
        specialFeatures: supplementary.specialFeatures,
      );
      merged = oxplayerPrepareMovieMediaStreams(merged, ref) ?? merged;
      state = merged;
    } catch (e) {
      log("Error loading staged movie details: $e");
    }
  }

  void setMediaStreamHelper(MediaStreamsModel changed) {
    state = state?.copyWith(mediaStreams: changed);
  }
}
