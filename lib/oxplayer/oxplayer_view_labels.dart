import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// OX-facing library folder labels (server [jellyfin.VirtualTVViewName] is source of truth).
abstract final class OxplayerViewLabels {
  static const tvLibraryName = 'Series';

  static ViewModel apply(ViewModel view) {
    if (!OxplayerConfig.isEnabled) return view;
    if (view.collectionType != CollectionType.tvshows) return view;
    if (view.name == tvLibraryName) return view;
    return view.copyWith(name: tvLibraryName);
  }

  static List<ViewModel> applyAll(List<ViewModel> views) => views.map(apply).toList();
}
