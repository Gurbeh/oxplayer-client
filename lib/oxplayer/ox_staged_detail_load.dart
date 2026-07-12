import 'dart:async';
import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_item_recommendations.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/ox_seerr_ratings.dart';
import 'package:fladder/oxplayer/ox_season_user_data.dart';
import 'package:fladder/oxplayer/ox_series_details_loader.dart';
import 'package:fladder/oxplayer/ox_virtual_episode_images.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

/// Merges freshly loaded shelves into [current] without dropping in-flight catalog data.
SeriesModel oxMergeSeriesSupplementary(
  SeriesModel current, {
  List<ItemBaseModel>? related,
  List<SeerrDashboardPosterModel>? seerrRelated,
  List<SeerrDashboardPosterModel>? seerrRecommended,
  String? seerrUrl,
  List<SpecialFeatureModel>? specialFeatures,
}) {
  return current.copyWith(
    related: related ?? current.related,
    seerrRelated: seerrRelated ?? current.seerrRelated,
    seerrRecommended: seerrRecommended ?? current.seerrRecommended,
    specialFeatures: specialFeatures ?? current.specialFeatures,
    overview: seerrUrl != null ? current.overview.copyWith(seerrUrl: seerrUrl) : current.overview,
  );
}

MovieModel oxMergeMovieSupplementary(
  MovieModel current, {
  List<ItemBaseModel>? related,
  List<SeerrDashboardPosterModel>? seerrRelated,
  List<SeerrDashboardPosterModel>? seerrRecommended,
  String? seerrUrl,
  List<SpecialFeatureModel>? specialFeatures,
}) {
  return current.copyWith(
    related: related ?? current.related,
    seerrRelated: seerrRelated ?? current.seerrRelated,
    seerrRecommended: seerrRecommended ?? current.seerrRecommended,
    specialFeatures: specialFeatures ?? current.specialFeatures,
    overview: seerrUrl != null ? current.overview.copyWith(seerrUrl: seerrUrl) : current.overview,
  );
}

Future<SeriesModel?> oxFetchSeriesCoreState(
  Ref ref,
  ItemBaseModel seriesModel,
  SeriesModel? previous,
) async {
  SeriesModel? newState;
  if (OxplayerEnv.isEnabled) {
    final oxItem = await oxFetchLibraryItemDetails(ref, seriesModel.id);
    if (oxItem != null && oxItem.model is SeriesModel) {
      newState = (oxItem.model as SeriesModel).copyWith(
        related: previous?.related ?? const [],
        seerrRelated: previous?.seerrRelated ?? const [],
        seerrRecommended: previous?.seerrRecommended ?? const [],
        availableEpisodes: previous?.availableEpisodes ?? const [],
        seasons: previous?.seasons ?? const [],
        canDownload: previous?.canDownload ?? false,
        specialFeatures: previous?.specialFeatures,
      );
    }
  }
  if (newState == null) {
    final api = ref.read(jellyApiProvider);
    final response = await api.usersUserIdItemsItemIdGet(itemId: seriesModel.id);
    if (response.body == null) return null;
    newState = (response.bodyOrThrow as SeriesModel).copyWith(
      related: previous?.related ?? const [],
      seerrRelated: previous?.seerrRelated ?? const [],
      seerrRecommended: previous?.seerrRecommended ?? const [],
      availableEpisodes: previous?.availableEpisodes ?? const [],
      seasons: previous?.seasons ?? const [],
      canDownload: previous?.canDownload ?? false,
      specialFeatures: previous?.specialFeatures,
    );
    if (OxplayerEnv.isEnabled) {
      final raw = await oxFetchLibraryItemJson(ref, seriesModel.id);
      oxApplyLibraryItemRatings(ref, seriesModel.id, raw != null ? oxRatingsFromItemJson(raw) : null);
    }
  }
  return newState;
}

Future<MovieModel?> oxFetchMovieCoreState(
  Ref ref,
  ItemBaseModel item,
  MovieModel? previous,
) async {
  MovieModel? newState;
  if (OxplayerEnv.isEnabled) {
    final oxItem = await oxFetchLibraryItemDetails(ref, item.id);
    if (oxItem != null && oxItem.model is MovieModel) {
      newState = (oxItem.model as MovieModel).copyWith(
        related: previous?.related ?? const [],
        seerrRelated: previous?.seerrRelated ?? const [],
        seerrRecommended: previous?.seerrRecommended ?? const [],
        specialFeatures: previous?.specialFeatures ?? const [],
      );
    }
  }
  if (newState == null) {
    final api = ref.read(jellyApiProvider);
    final response = await api.usersUserIdItemsItemIdGet(itemId: item.id);
    if (response.body == null) return null;
    newState = (response.bodyOrThrow as MovieModel).copyWith(
      related: previous?.related ?? const [],
      seerrRelated: previous?.seerrRelated ?? const [],
      seerrRecommended: previous?.seerrRecommended ?? const [],
      specialFeatures: previous?.specialFeatures ?? const [],
    );
    if (OxplayerEnv.isEnabled) {
      final raw = await oxFetchLibraryItemJson(ref, item.id);
      oxApplyLibraryItemRatings(ref, item.id, raw != null ? oxRatingsFromItemJson(raw) : null);
    }
  }
  return newState;
}

Future<SeriesModel> oxLoadSeriesCatalogPhase(
  Ref ref,
  SeriesModel base,
  String seriesId, {
  Future<OxSeriesCatalogLoad>? prefetchCatalog,
}) async {
  final api = ref.read(jellyApiProvider);

  final Response<BaseItemDtoQueryResult?> seasons;
  List<BaseItemDto> episodeItems;
  if (OxplayerEnv.isEnabled) {
    final catalog = prefetchCatalog != null
        ? await prefetchCatalog
        : await oxFetchSeriesCatalogBySeason(api, seriesId);
    seasons = catalog.seasons;
    episodeItems = catalog.episodeItems;
  } else {
    seasons = await api.showsSeriesIdSeasonsGet(
      seriesId: seriesId,
      enableUserData: false,
    );
    final episodes = await api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      enableUserData: true,
      fields: oxEpisodeListFields([
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.candownload,
      ]),
    );
    episodeItems = episodes.body?.items ?? const [];
  }

  final newEpisodes = oxApplyVirtualEpisodeImages(
    EpisodeModel.episodesFromDto(episodeItems, ref),
    episodeItems,
    ref,
  );

  final episodesCanDownload = newEpisodes.any((episode) => episode.canDownload == true);

  var newState = base.copyWith(
    seasons: SeasonModel.seasonsFromDto(seasons.body?.items, ref).map(
      (element) {
        final seasonEpisodes = newEpisodes.where((episode) => episode.season == element.season);
        final userData = OxplayerEnv.isEnabled
            ? oxSeasonUserDataFromEpisodes(seasonEpisodes)
            : () {
                final unPlayedCount = seasonEpisodes
                    .where((episode) =>
                        episode.status == EpisodeStatus.available && episode.userData.played == false)
                    .length;
                return UserData(
                  unPlayedItemCount: unPlayedCount,
                  played: unPlayedCount == 0,
                );
              }();
        return element.copyWith(
          canDownload: true,
          episodes: seasonEpisodes.toList(),
          userData: userData,
        );
      },
    ).toList(),
  );

  return newState.copyWith(
    canDownload: episodesCanDownload,
    availableEpisodes: newEpisodes,
  );
}

Future<({
  List<ItemBaseModel> related,
  List<SeerrDashboardPosterModel> seerrRelated,
  List<SeerrDashboardPosterModel> seerrRecommended,
  String? seerrUrl,
  List<SpecialFeatureModel> specialFeatures,
})> oxLoadSeriesSupplementaryPhase(
  Ref ref,
  String seriesId,
  SeriesModel state,
) async {
  final api = ref.read(jellyApiProvider);

  List<BaseItemDto> specialFeaturesDto;
  try {
    specialFeaturesDto = (await api.itemsItemIdSpecialFeaturesGet(itemId: seriesId)).body ?? [];
  } on Exception catch (e, s) {
    specialFeaturesDto = [];
    log(
      "Failed to get special features for series id $seriesId due to $e",
      level: logging.Level.WARNING.value,
      error: e,
      stackTrace: s,
    );
  }

  final related = await ref.read(relatedUtilityProvider).relatedContent(seriesId);
  List<SeerrDashboardPosterModel> seerrRelated = const [];
  List<SeerrDashboardPosterModel> seerrRecommended = const [];
  String? seerrUrl;

  final seerrCreds = ref.read(userProvider)?.seerrCredentials;
  final tmdbId = state.tmdbId;
  if (OxplayerEnv.isEnabled) {
    if (seerrCreds?.isConfigured == true && tmdbId != null) {
      seerrUrl = 'ox';
    }
    seerrRecommended = await oxFetchItemRecommendations(ref, seriesId);
  } else if (seerrCreds?.isConfigured == true && tmdbId != null) {
    final seerr = ref.read(seerrApiProvider);
    seerrRelated = await seerr.discoverRelatedSeries(tmdbId: tmdbId);
    seerrRecommended = await seerr.discoverRecommendedSeries(tmdbId: tmdbId);
    final seerrPoster = await seerr.fetchDashboardPosterFromIds(
      tmdbId: tmdbId,
      mediaType: SeerrMediaType.tvshow,
    );
    final status = seerrPoster?.mediaInfo?.mediaStatus;
    if (status != SeerrMediaStatus.unknown) {
      final seerrServerUrl = ref.read(userProvider.select((value) => value?.seerrCredentials?.serverUrl));
      seerrUrl = '${seerrServerUrl}tv/$tmdbId';
    }
  }

  return (
    related: related.body ?? const [],
    seerrRelated: seerrRelated,
    seerrRecommended: seerrRecommended,
    seerrUrl: seerrUrl,
    specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeaturesDto, ref),
  );
}

Future<({
  List<ItemBaseModel> related,
  List<SeerrDashboardPosterModel> seerrRelated,
  List<SeerrDashboardPosterModel> seerrRecommended,
  String? seerrUrl,
  List<SpecialFeatureModel> specialFeatures,
})> oxLoadMovieSupplementaryPhase(
  Ref ref,
  String itemId,
  MovieModel state,
) async {
  final api = ref.read(jellyApiProvider);

  List<BaseItemDto> specialFeaturesDto;
  try {
    specialFeaturesDto = (await api.itemsItemIdSpecialFeaturesGet(itemId: itemId)).body ?? [];
  } on Exception catch (e, s) {
    specialFeaturesDto = [];
    log(
      "Failed to get special features for movie id $itemId due to $e",
      level: logging.Level.WARNING.value,
      error: e,
      stackTrace: s,
    );
  }

  final related = await ref.read(relatedUtilityProvider).relatedContent(itemId);
  List<SeerrDashboardPosterModel> seerrRelated = const [];
  List<SeerrDashboardPosterModel> seerrRecommended = const [];
  String? seerrUrl;

  final seerrCreds = ref.read(userProvider)?.seerrCredentials;
  final tmdbId = state.tmdbId;
  if (OxplayerEnv.isEnabled) {
    if (seerrCreds?.isConfigured == true && tmdbId != null) {
      seerrUrl = 'ox';
    }
    seerrRecommended = await oxFetchItemRecommendations(ref, itemId);
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

  return (
    related: related.body ?? const [],
    seerrRelated: seerrRelated,
    seerrRecommended: seerrRecommended,
    seerrUrl: seerrUrl,
    specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeaturesDto, ref),
  );
}

void oxPrefetchMovieSeerrRatings(Ref ref, String itemId, int? tmdbId) {
  if (!OxplayerEnv.isEnabled || tmdbId == null || tmdbId <= 0) return;
  if (!oxSeerrRatingsMissingRt(ref.read(oxLibraryItemRatingsProvider(itemId)))) return;
  unawaited(() async {
    try {
      final fromSeerr = await ref.read(seerrApiProvider).movieRatings(tmdbId);
      final merged = oxMergeSeerrRatings(
        fromSeerr,
        ref.read(oxLibraryItemRatingsProvider(itemId)),
      );
      oxApplyLibraryItemRatings(ref, itemId, merged);
    } catch (_) {}
  }());
}
