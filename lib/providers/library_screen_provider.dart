import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/recommended_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/localization_helper.dart';

part 'library_screen_provider.freezed.dart';
part 'library_screen_provider.g.dart';

Set<LibraryViewType> libraryLoadTypes(LibraryScreenModel state) {
  if (OxplayerConfig.isEnabled && state.viewType.isEmpty) {
    return {LibraryViewType.recommended};
  }
  return state.viewType;
}

enum LibraryViewType {
  recommended,
  favourites,
  genres;

  const LibraryViewType();

  String label(BuildContext context) => switch (this) {
        LibraryViewType.recommended => context.localized.recommended,
        LibraryViewType.favourites => context.localized.favorites,
        LibraryViewType.genres => context.localized.genre(2),
      };

  IconData get icon => switch (this) {
        LibraryViewType.recommended => IconsaxPlusLinear.star,
        LibraryViewType.favourites => IconsaxPlusLinear.heart,
        LibraryViewType.genres => IconsaxPlusLinear.hierarchy_3,
      };

  IconData get iconSelected => switch (this) {
        LibraryViewType.recommended => IconsaxPlusBold.star,
        LibraryViewType.favourites => IconsaxPlusBold.heart,
        LibraryViewType.genres => IconsaxPlusBold.hierarchy_3,
      };
}

@Freezed(fromJson: false, toJson: false, copyWith: true)
abstract class LibraryScreenModel with _$LibraryScreenModel {
  factory LibraryScreenModel({
    @Default([]) List<ViewModel> views,
    ViewModel? selectedViewModel,
    @Default({LibraryViewType.recommended, LibraryViewType.favourites}) Set<LibraryViewType> viewType,
    @Default([]) List<RecommendedModel> recommendations,
    @Default([]) List<RecommendedModel> genres,
    @Default([]) List<ItemBaseModel> favourites,
  }) = _LibraryScreenModel;
}

@Riverpod(keepAlive: true)
class LibraryScreen extends _$LibraryScreen {
  late final JellyService api = ref.read(jellyApiProvider);

  @override
  LibraryScreenModel build() => LibraryScreenModel(
        viewType: OxplayerConfig.isEnabled
            ? {}
            : {LibraryViewType.recommended, LibraryViewType.favourites},
      );

  Future<void> fetchAllLibraries() async {
    Future<void> load() async {
      final cachedViews = ref.read(viewsProvider);
      final List<ViewModel> viewsList;
      if (cachedViews.views.isNotEmpty && !cachedViews.loading) {
        viewsList = cachedViews.views;
      } else {
        final views = await ref.read(viewsProvider.notifier).fetchViews();
        viewsList = views?.views.toList() ?? [];
      }
      state = state.copyWith(
        views: viewsList,
      );
      if (state.views.isEmpty) return;
      final viewModel = state.selectedViewModel ?? state.views.firstOrNull;
      if (viewModel == null) return;
      if (state.selectedViewModel?.id != viewModel.id) {
        await selectLibrary(viewModel);
      } else {
        state = state.copyWith(selectedViewModel: viewModel);
      }
      await loadLibrary(viewModel);
    }

    if (OxplayerConfig.isEnabled) {
      await OxplayerScreenTelemetry.trackLoad(screen: 'library', phase: 'fetch', load: load);
      return;
    }
    await load();
  }

  Future<void> selectLibrary(ViewModel viewModel) async {
    state = state.copyWith(
      selectedViewModel: viewModel,
      recommendations: const [],
      favourites: const [],
      genres: const [],
    );
  }

  Future<void> setViewType(Set<LibraryViewType> type) async {
    state = state.copyWith(viewType: type);
    final view = state.selectedViewModel;
    if (view != null) {
      await loadLibrary(view);
    }
  }

  Future<Response?> loadLibrary(ViewModel viewModel) async {
    final loadTypes = libraryLoadTypes(state);
    final loadRecommended = loadTypes.contains(LibraryViewType.recommended);
    final loadFavouritesSection = loadTypes.contains(LibraryViewType.favourites);
    final loadGenresSection = loadTypes.contains(LibraryViewType.genres);

    final results = await Future.wait<dynamic>([
      loadRecommended ? _fetchRecommendations(viewModel) : Future<dynamic>.value(null),
      loadFavouritesSection ? _fetchFavourites(viewModel) : Future<dynamic>.value(null),
      loadGenresSection ? _fetchGenres(viewModel) : Future<dynamic>.value(null),
    ]);

    state = state.copyWith(
      recommendations: loadRecommended ? (results[0] as List<RecommendedModel>?) ?? const [] : state.recommendations,
      favourites: loadFavouritesSection ? (results[1] as List<ItemBaseModel>?) ?? const [] : state.favourites,
      genres: loadGenresSection ? (results[2] as List<RecommendedModel>?) ?? const [] : state.genres,
    );
    return null;
  }

  Future<List<RecommendedModel>> _fetchRecommendations(ViewModel viewModel) async {
    final collectionType = viewModel.collectionType;
    final fetchContinue = collectionType == CollectionType.movies ||
        collectionType == CollectionType.tvshows ||
        collectionType == CollectionType.homevideos;
    final fetchNextUp = collectionType == CollectionType.tvshows;
    final fetchMovieRecs = collectionType == CollectionType.movies;
    final fetchLatest = collectionType != CollectionType.livetv;

    final resumeFuture = fetchContinue
        ? api.usersUserIdItemsResumeGet(
            parentId: viewModel.id,
            limit: 9,
            enableUserData: true,
            fields: [
              ItemFields.overview,
              ItemFields.primaryimageaspectratio,
            ],
            enableImageTypes: [
              ImageType.primary,
              ImageType.banner,
              ImageType.screenshot,
            ],
            mediaTypes: [MediaType.video],
            enableTotalRecordCount: false,
          )
        : Future<Response?>.value(null);

    final nextUpFuture = fetchNextUp
        ? api.showsNextUpGet(
            parentId: viewModel.id,
            limit: 9,
            imageTypeLimit: 1,
            fields: [
              ItemFields.mediasourcecount,
              ItemFields.primaryimageaspectratio,
              ItemFields.overview,
            ],
          )
        : Future<Response?>.value(null);

    final moviesRecFuture = fetchMovieRecs
        ? api.moviesRecommendationsGet(
            parentId: viewModel.id,
            categoryLimit: 6,
            fields: [
              ItemFields.overview,
              ItemFields.primaryimageaspectratio,
            ],
            itemLimit: 9,
          )
        : Future<Response<List<RecommendationDto>?>?>.value(null);

    final latestFuture = fetchLatest ? _fetchLatestForView(viewModel) : Future<Response?>.value(null);

    final results = await Future.wait<dynamic>([
      resumeFuture,
      moviesRecFuture,
      nextUpFuture,
      latestFuture,
    ]);

    final shelves = <RecommendedModel>[];

    if (fetchContinue) {
      final resume = results[0] as Response?;
      shelves.add(
        RecommendedModel(
          name: const Continue(),
          posters: _mapItemPosters(resume?.body?.items),
          type: null,
        ),
      );
    }

    if (fetchNextUp) {
      final nextUp = results[2] as Response?;
      shelves.add(
        RecommendedModel(
          name: const NextUp(),
          posters: _mapItemPosters(nextUp?.body?.items),
          type: null,
        ),
      );
    }

    if (fetchLatest) {
      final latest = results[3] as Response?;
      shelves.add(
        RecommendedModel(
          name: const Latest(),
          posters: _latestPosters(latest, collectionType),
          type: null,
        ),
      );
    }

    if (fetchMovieRecs) {
      final moviesRecommendations = results[1] as Response<List<RecommendationDto>?>?;
      shelves.addAll(
        moviesRecommendations?.body?.map((e) => RecommendedModel.fromBaseDto(e, ref)).toList() ?? const [],
      );
    }

    return shelves..removeWhere((element) => element.posters.isEmpty);
  }

  Future<Response> _fetchLatestForView(ViewModel viewModel) {
    if (viewModel.collectionType == CollectionType.playlists) {
      return api.itemsGet(
        parentId: viewModel.id,
        sortBy: [ItemSortBy.datecreated, ItemSortBy.sortname],
        sortOrder: [SortOrder.descending],
        limit: 9,
        includeItemTypes: [BaseItemKind.playlist],
        enableImageTypes: [ImageType.primary],
        fields: [
          ItemFields.mediasourcecount,
          ItemFields.primaryimageaspectratio,
          ItemFields.overview,
        ],
        enableTotalRecordCount: false,
      );
    }

    return api.usersUserIdItemsGet(
      parentId: viewModel.id,
      sortBy: [ItemSortBy.datelastcontentadded, ItemSortBy.datecreated, ItemSortBy.sortname],
      sortOrder: [SortOrder.descending],
      limit: 9,
      includeItemTypes: viewModel.collectionType.itemKinds.map((e) => e.dtoKind).toList(),
    );
  }

  List<ItemBaseModel> _latestPosters(Response? response, CollectionType? collectionType) {
    if (response == null) return const [];
    if (collectionType == CollectionType.playlists) {
      return response.body?.items ?? const [];
    }
    return _mapItemPosters(response.body?.items);
  }

  Future<List<ItemBaseModel>> _fetchFavourites(ViewModel viewModel) async {
    final response = await api.itemsGet(
      parentId: viewModel.id,
      isFavorite: true,
      recursive: true,
      limit: 9,
      includeItemTypes: viewModel.collectionType.itemKinds.map((e) => e.dtoKind).toList(),
      enableImageTypes: [ImageType.primary],
      fields: [
        ItemFields.mediasourcecount,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
      enableTotalRecordCount: false,
    );

    return response.body?.items ?? [];
  }

  Future<List<RecommendedModel>> _fetchGenres(ViewModel viewModel) async {
    final genres = await api.genresGet(
      sortBy: [ItemSortBy.sortname],
      sortOrder: [SortOrder.ascending],
      includeItemTypes:
          viewModel.collectionType == CollectionType.movies ? [BaseItemKind.movie] : [BaseItemKind.series],
      parentId: viewModel.id,
    );

    final filteredGenres = (genres.body?.items?.map(
              (item) => GenreItems(id: item.id ?? "", name: item.name ?? ""),
            ) ??
            [])
        .toList();

    if (filteredGenres.isEmpty) return const [];

    final futures = filteredGenres.map((genre) {
      return api
          .itemsGet(
        parentId: viewModel.id,
        genreIds: [genre.id],
        limit: 9,
        recursive: true,
        includeItemTypes: viewModel.collectionType.itemKinds.map((e) => e.dtoKind).toList(),
        enableImageTypes: [ImageType.primary],
        fields: [
          ItemFields.mediasourcecount,
          ItemFields.primaryimageaspectratio,
          ItemFields.overview,
        ],
        sortBy: [ItemSortBy.random],
        enableTotalRecordCount: false,
        imageTypeLimit: 1,
        sortOrder: [SortOrder.ascending],
      )
          .then((response) {
        final items = response.body?.items;
        if (items != null && items.isNotEmpty) {
          return RecommendedModel(name: Other(genre.name), posters: items);
        }
        return null;
      });
    }).toList();

    final results = await Future.wait(futures);

    return results.whereType<RecommendedModel>().toList();
  }

  List<ItemBaseModel> _mapItemPosters(Iterable<dynamic>? items) {
    if (items == null) return const [];
    return items.map<ItemBaseModel>((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
  }

  void clear() {
    state = LibraryScreenModel(
      viewType: OxplayerConfig.isEnabled
          ? {}
          : {LibraryViewType.recommended, LibraryViewType.favourites},
    );
  }
}
