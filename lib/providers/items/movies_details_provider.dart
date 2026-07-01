import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:logging/logging.dart' as logging;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_item_recommendations.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_share.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

part 'movies_details_provider.g.dart';

@riverpod
class MovieDetails extends _$MovieDetails {
  late final JellyService api = ref.read(jellyApiProvider);

  @override
  MovieModel? build(String arg) => null;

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    Future<Response?> load() async {
      try {
      if (item is MovieModel) {
        state = state ?? item;
      }
      MovieModel? newState;
      if (OxplayerEnv.isEnabled) {
        final oxItem = await oxFetchLibraryItemDetails(ref, item.id);
        if (oxItem != null && oxItem.model is MovieModel) {
          newState = (oxItem.model as MovieModel).copyWith(
            related: state?.related ?? const [],
            seerrRelated: state?.seerrRelated ?? const [],
            seerrRecommended: state?.seerrRecommended ?? const [],
          );
        }
      }
      if (newState == null) {
        final response = await api.usersUserIdItemsItemIdGet(itemId: item.id);
        if (response.body == null) return null;
        newState = (response.bodyOrThrow as MovieModel).copyWith(
          related: state?.related ?? const [],
          seerrRelated: state?.seerrRelated ?? const [],
          seerrRecommended: state?.seerrRecommended ?? const [],
        );
        if (OxplayerEnv.isEnabled) {
          final raw = await oxFetchLibraryItemJson(ref, item.id);
          oxApplyLibraryItemRatings(ref, item.id, raw != null ? oxRatingsFromItemJson(raw) : null);
        }
      }

      state = newState;

      if (OxplayerEnv.isEnabled && oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(item.id)))) {
        final tmdbId = newState.tmdbId;
        if (tmdbId != null) {
          final fromSeerr = await ref.read(seerrApiProvider).movieRatings(tmdbId);
          final merged = oxMergeSeerrRatings(
            fromSeerr,
            ref.read(oxLibraryItemRatingsProvider(item.id)),
          );
          oxApplyLibraryItemRatings(ref, item.id, merged);
        }
      }

      List<BaseItemDto> specialFeatures;
      try {
        specialFeatures = (await api.itemsItemIdSpecialFeaturesGet(itemId: item.id)).body ?? [];
      } on Exception catch (e, s) {
        specialFeatures = [];
        log("Failed to get special features for movie id ${item.id} due to $e",
            level: logging.Level.WARNING.value, error: e, stackTrace: s);
      }

      final related = await ref.read(relatedUtilityProvider).relatedContent(item.id);
      final List<SpecialFeatureModel> specialFeatureModel =
          SpecialFeatureModel.specialFeaturesFromDto(specialFeatures, ref).toList();

      List<SeerrDashboardPosterModel> seerrRelated = const [];
      List<SeerrDashboardPosterModel> seerrRecommended = const [];

      String? seerrUrl;

      final seerrCreds = ref.read(userProvider)?.seerrCredentials;
      final tmdbId = newState.tmdbId;
      if (OxplayerEnv.isEnabled) {
        if (seerrCreds?.isConfigured == true && tmdbId != null) {
          seerrUrl = 'ox';
        }
        seerrRecommended = await oxFetchItemRecommendations(ref, item.id);
      } else if (seerrCreds?.isConfigured == true && tmdbId != null) {
        final seerr = ref.read(seerrApiProvider);
        seerrRelated = await seerr.discoverRelatedMovies(tmdbId: tmdbId);
        seerrRecommended = await seerr.discoverRecommendedMovies(tmdbId: tmdbId);
        final seerrPoster = await seerr.fetchDashboardPosterFromIds(
          tmdbId: tmdbId,
          mediaType: SeerrMediaType.movie,
        );
        final status = seerrPoster?.mediaInfo?.mediaStatus;
        if (status != SeerrMediaStatus.unknown) {
          final seerrServerUrl = ref.read(userProvider.select((value) => value?.seerrCredentials?.serverUrl));
          seerrUrl = '${seerrServerUrl}movie/$tmdbId';
        }
      }

      state = newState.copyWith(
          related: related.body,
          seerrRelated: seerrRelated,
          seerrRecommended: seerrRecommended,
          overview: state?.overview.copyWith(
            seerrUrl: seerrUrl,
          ),
          specialFeatures: specialFeatureModel);
      if (OxplayerConfig.isEnabled) {
        state = oxplayerApplyShareMediaSourceToMovie(state, ref);
      }
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

  void setMediaStreamHelper(MediaStreamsModel changed) {
    state = state?.copyWith(mediaStreams: changed);
  }
}
