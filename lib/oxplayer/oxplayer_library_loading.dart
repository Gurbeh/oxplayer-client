import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/library_screen_provider.dart';

/// OX: no filter chips selected still loads/shows recommended shelves.
Set<LibraryViewType> oxLibraryLoadTypes(LibraryScreenModel state) => libraryLoadTypes(state);

bool oxShowLibraryRecommended(LibraryScreenModel state) {
  if (OxplayerConfig.isEnabled) {
    return state.viewType.isEmpty || state.viewType.contains(LibraryViewType.recommended);
  }
  return state.viewType.contains(LibraryViewType.recommended);
}

bool oxLibraryHasCachedContent(LibraryScreenModel state) {
  if (state.views.isEmpty || state.selectedViewModel == null) return false;
  final types = oxLibraryLoadTypes(state);
  if (types.isEmpty) return false;
  if (types.contains(LibraryViewType.recommended) && state.recommendations.isNotEmpty) {
    return true;
  }
  if (types.contains(LibraryViewType.favourites) && state.favourites.isNotEmpty) {
    return true;
  }
  if (types.contains(LibraryViewType.genres) && state.genres.isNotEmpty) {
    return true;
  }
  return false;
}

bool oxShowLibraryListSkeleton({
  required bool refreshing,
  required LibraryScreenModel state,
}) {
  return OxplayerConfig.isEnabled && refreshing && !oxLibraryHasCachedContent(state);
}
