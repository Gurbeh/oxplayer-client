import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/library_search/library_search_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/map_bool_helper.dart';

/// OX: smaller first page for library grid browse (poster cards refetch detail on open).
const oxLibrarySearchInitialPageSize = 48;

/// OX: defer filter metadata until user opens filter UI.
bool oxLibrarySearchDeferFilters(LibrarySearchModel state) {
  if (!OxplayerConfig.isEnabled) return false;
  return !state.filters.hasActiveFilters && state.searchQuery.isEmpty;
}

int oxLibrarySearchPageSize(int configuredSize) {
  if (!OxplayerConfig.isEnabled) return configuredSize;
  if (configuredSize <= 0) return configuredSize;
  if (configuredSize > oxLibrarySearchInitialPageSize) {
    return oxLibrarySearchInitialPageSize;
  }
  return configuredSize;
}

/// Reuse home/dashboard views instead of GET /Users/{id}/Views on library open.
Map<ViewModel, bool>? oxLibrarySearchViewsFromCache(Ref ref, String? viewModelId) {
  if (!OxplayerConfig.isEnabled || viewModelId == null || viewModelId.isEmpty) {
    return null;
  }
  final cached = ref.read(viewsProvider);
  if (cached.views.isEmpty || cached.loading) return null;
  final selected = cached.views.firstWhere(
    (element) => element.id == viewModelId,
    orElse: () => cached.views.first,
  );
  if (selected.id != viewModelId) return null;
  return {for (final view in cached.views) view: view.id == viewModelId};
}

/// Prime item types from the selected library without GET /Genres + /Items/Filters2.
LibrarySearchModel oxLibrarySearchPrimeCollectionTypes(LibrarySearchModel state) {
  if (!OxplayerConfig.isEnabled || !state.views.hasEnabled) return state;
  final enabledKinds = state.views.included.map((e) => e.collectionType.itemKinds).expand((e) => e);
  return state.copyWith(
    filters: state.filters.copyWith(
      types: state.filters.types.setAll(false).setKeys(enabledKinds, true),
    ),
  );
}

/// Lighter DTO for poster grid — keeps ChildCount for series episode counts.
List<ItemFields> oxLibrarySearchListFields(CollectionType? collectionType) {
  if (!OxplayerConfig.isEnabled) {
    return const [];
  }
  return [
    ItemFields.parentid,
    ItemFields.primaryimageaspectratio,
    if (collectionType == CollectionType.tvshows) ItemFields.childcount,
  ];
}
