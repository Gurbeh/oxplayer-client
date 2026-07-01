import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Public marketing-site origin for share links.
const kOxplayerShareOrigin = 'https://oxplayer.app';

/// Pending [mediaSourceId] from a share deep link, keyed by catalog item id.
final oxplayerShareMediaSourceIdProvider = StateProvider.autoDispose.family<String?, String>((ref, catalogId) => null);

String? _bufferedShareCatalogId;
String? _bufferedShareMediaSourceId;

/// Called from [deepLinkBuilder] before auth is available (no [WidgetRef]).
void oxplayerBufferShareMediaSource({
  required String catalogId,
  String? mediaSourceId,
}) {
  if (!OxplayerConfig.isEnabled) return;
  final id = catalogId.trim();
  if (id.isEmpty) return;
  _bufferedShareCatalogId = id;
  final msId = mediaSourceId?.trim();
  _bufferedShareMediaSourceId = (msId == null || msId.isEmpty) ? null : msId;
}

void oxplayerFlushBufferedShareMediaSource(WidgetRef ref) {
  final catalogId = _bufferedShareCatalogId;
  final mediaSourceId = _bufferedShareMediaSourceId;
  _bufferedShareCatalogId = null;
  _bufferedShareMediaSourceId = null;
  if (catalogId == null) return;
  if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
    ref.read(oxplayerShareMediaSourceIdProvider(catalogId).notifier).state = mediaSourceId;
  }
}

/// Read buffered share [mediaSourceId] before flush (for pending route paths).
String? oxplayerPeekBufferedShareMediaSourceId(String catalogId) {
  if (_bufferedShareCatalogId == catalogId) {
    return _bufferedShareMediaSourceId;
  }
  return null;
}

String oxplayerBuildShareUrl(String catalogId, {String? mediaSourceId}) {
  final id = catalogId.trim();
  final base = '$kOxplayerShareOrigin/share/$id';
  final msId = mediaSourceId?.trim();
  if (msId == null || msId.isEmpty) return base;
  return '$base?mediaSourceId=${Uri.encodeQueryComponent(msId)}';
}

/// Selected file variant for share links (movies/episodes only).
String? oxplayerShareMediaSourceIdFromItem(ItemBaseModel item) {
  if (item is! ItemStreamModel) return null;
  final id = item.mediaStreams.currentVersionStream?.id?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
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

String? oxplayerMediaSourceIdFromShareUri(Uri uri) {
  final fromQuery = uri.queryParameters['mediaSourceId']?.trim();
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
  return null;
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
      final id = parts[1].split('/').first.split('?').first.trim();
      return id.isEmpty ? null : id;
    }
  }
  return null;
}

bool oxplayerIsShareWebHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host == 'oxplayer.app' || host == 'www.oxplayer.app';
}

ItemBaseModel oxplayerApplyShareMediaSource(ItemBaseModel item, Ref ref) {
  if (!OxplayerConfig.isEnabled) return item;
  final preferredId = _resolveShareMediaSourceId(ref, item.id);
  if (preferredId == null || preferredId.isEmpty) return item;
  _clearShareMediaSourceId(ref, item.id);

  if (item is! ItemStreamModel) return item;
  final streams = item.mediaStreams;
  final idx = streams.versionStreams.indexWhere((v) => v.id == preferredId);
  if (idx < 0) return item;

  final updated = streams.copyWith(versionStreamIndex: idx);
  return switch (item) {
    MovieModel m => m.copyWith(mediaStreams: updated),
    EpisodeModel e => e.copyWith(mediaStreams: updated),
    _ => item,
  };
}

String? _resolveShareMediaSourceId(Ref ref, String catalogId) {
  if (_bufferedShareCatalogId == catalogId && _bufferedShareMediaSourceId != null) {
    return _bufferedShareMediaSourceId;
  }
  return ref.read(oxplayerShareMediaSourceIdProvider(catalogId));
}

void _clearShareMediaSourceId(Ref ref, String catalogId) {
  if (_bufferedShareCatalogId == catalogId) {
    _bufferedShareCatalogId = null;
    _bufferedShareMediaSourceId = null;
  }
  ref.read(oxplayerShareMediaSourceIdProvider(catalogId).notifier).state = null;
}

MovieModel? oxplayerApplyShareMediaSourceToMovie(MovieModel? movie, Ref ref) {
  if (movie == null) return null;
  final applied = oxplayerApplyShareMediaSource(movie, ref);
  return applied is MovieModel ? applied : movie;
}

EpisodeModel? oxplayerApplyShareMediaSourceToEpisode(EpisodeModel? episode, Ref ref) {
  if (episode == null) return null;
  final applied = oxplayerApplyShareMediaSource(episode, ref);
  return applied is EpisodeModel ? applied : episode;
}
