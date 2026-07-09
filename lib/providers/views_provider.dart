import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';

//Known supported collection types
const enableCollectionTypes = {
  CollectionType.movies,
  CollectionType.books,
  CollectionType.tvshows,
  CollectionType.homevideos,
  CollectionType.boxsets,
  CollectionType.playlists,
  CollectionType.photos,
  CollectionType.livetv,
  CollectionType.folders,
  CollectionType.music,
  CollectionType.musicvideos,
};

final viewsProvider = StateNotifierProvider<ViewsNotifier, ViewsModel>((ref) {
  return ViewsNotifier(ref);
});

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<ViewsModel?> fetchViews() async {
    Future<ViewsModel?> load() async {
      if (state.loading) return null;
      state = state.copyWith(loading: true);
      final showAllCollections = ref.read(clientSettingsProvider.select((value) => value.showAllCollectionTypes));
      final response = await api.usersUserIdViewsGet();
    final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref)).where((element) {
      return showAllCollections ? true : enableCollectionTypes.contains(element.collectionType);
    });

    List<ViewModel> newList = [];

    if (createdViews != null) {
      if (OxplayerConfig.isEnabled) {
        newList = createdViews.toList();
        _publishViews(newList, loading: true);

        await Future.wait(
          newList.map((view) async {
            final updated = await _fetchRecentlyAdded(view, showAllCollections: showAllCollections);
            final index = newList.indexWhere((element) => element.id == updated.id);
            if (index == -1) return;
            newList[index] = updated;
            _publishViews(newList, loading: true);
          }),
        );
      } else {
        newList = await Future.wait(
          createdViews.map((e) => _fetchRecentlyAdded(e, showAllCollections: showAllCollections)),
        );
      }
    }

    state = state.copyWith(
        views: _applyLibraryOrdering(newList),
        dashboardViews: _applyLibraryOrdering(newList
            .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
            .toList()),
        loading: false,
        loaded: true);
    return state;
    }

    if (OxplayerConfig.isEnabled) {
      return OxplayerScreenTelemetry.trackLoad(screen: 'home', phase: 'views', load: load);
    }
    return load();
  }

  Future<ViewModel> _fetchRecentlyAdded(ViewModel view, {required bool showAllCollections}) async {
    if (ref.read(userProvider)?.latestItemsExcludes.contains(view.id) == true) return view;
    final recents = await api.usersUserIdItemsLatestGet(
      parentId: view.id,
      imageTypeLimit: 1,
      limit: 16,
      includeItemTypes: (view.collectionType == CollectionType.books && !showAllCollections) ? [BaseItemKind.book] : null,
      enableImageTypes: [
        ImageType.primary,
        ImageType.backdrop,
        ImageType.thumb,
      ],
      fields: [
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
    );
    return view.copyWith(recentlyAdded: recents.body?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList());
  }

  void _publishViews(List<ViewModel> views, {required bool loading}) {
    state = state.copyWith(
      views: _applyLibraryOrdering(views),
      dashboardViews: _applyLibraryOrdering(
        views
            .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
            .toList(),
      ),
      loading: loading,
    );
  }

  List<ViewModel> _applyLibraryOrdering(List<ViewModel> views) {
    final orderedViews = ref.read(userProvider)?.userConfiguration?.orderedViews ?? [];
    if (orderedViews.isEmpty) return views;

    final viewMap = {for (var v in views) v.id: v};
    final ordered = <ViewModel>[];

    for (final id in orderedViews) {
      final view = viewMap.remove(id);
      if (view != null) ordered.add(view);
    }
    ordered.addAll(viewMap.values);
    return ordered;
  }

  void clear() {
    state = ViewsModel();
  }
}
