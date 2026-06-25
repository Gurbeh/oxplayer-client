import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';

/// Public marketing-site origin for share links.
const kOxplayerShareOrigin = 'https://oxplayer.app';

String oxplayerBuildShareUrl(String catalogId) {
  final id = catalogId.trim();
  return '$kOxplayerShareOrigin/share/$id';
}

/// Share is enabled for library movies/series/seasons/episodes, not home videos.
bool oxIsShareableItem(ItemBaseModel item) {
  if (item.jellyType == BaseItemKind.video) return false;

  final isSupportedType = switch (item) {
    MovieModel() || SeriesModel() || SeasonModel() || EpisodeModel() => true,
    _ => false,
  };
  if (!isSupportedType) return false;

  if (item is MovieModel) {
    final tmdb = item.providerIds?['Tmdb']?.toString() ?? '';
    if (tmdb.startsWith('general:')) return false;
  }

  return item.id.trim().isNotEmpty;
}

/// Parse catalog id from `https://oxplayer.app/share/{id}` or `oxplayer:///share/{id}`.
String? oxplayerCatalogIdFromShareUri(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.length >= 2 && segments[0] == 'share') {
    final id = segments[1].trim();
    return id.isEmpty ? null : id;
  }
  if (uri.path.contains('/share/')) {
    final parts = uri.path.split('/share/');
    if (parts.length == 2) {
      final id = parts[1].split('/').first.trim();
      return id.isEmpty ? null : id;
    }
  }
  return null;
}

bool oxplayerIsShareWebHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'oxplayer.app' || host == 'www.oxplayer.app';
}
