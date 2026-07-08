import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/api_provider.dart';

part 'ox_watchlist_dashboard.g.dart';

const _watchLaterPlaylistName = 'Watch Later';
const _dashboardLimit = 16;

bool _isWatchLaterPlaylistName(String? name) {
  final normalized = name?.trim().toLowerCase();
  return normalized == _watchLaterPlaylistName.toLowerCase() || normalized == 'watchlist';
}

class OxWatchlistDashboardData {
  const OxWatchlistDashboardData({
    this.playlistId,
    this.items = const [],
  });

  final String? playlistId;
  final List<ItemBaseModel> items;

  static const empty = OxWatchlistDashboardData();
}

@riverpod
Future<OxWatchlistDashboardData> oxWatchlistDashboard(Ref ref) async {
  if (!OxplayerEnv.isEnabled) return OxWatchlistDashboardData.empty;

  final api = ref.read(jellyApiProvider);
  final playlistsResponse = await api.usersUserIdItemsGet(
    recursive: true,
    includeItemTypes: [BaseItemKind.playlist],
  );
  final playlists = playlistsResponse.body?.items ?? const <BaseItemDto>[];
  BaseItemDto? watchLater;
  for (final playlist in playlists) {
    if (_isWatchLaterPlaylistName(playlist.name)) {
      watchLater = playlist;
      break;
    }
  }
  final playlistId = watchLater?.id;
  if (playlistId == null || playlistId.isEmpty) {
    return OxWatchlistDashboardData.empty;
  }

  final itemsResponse = await api.playlistsPlaylistIdItemsGet(
    playlistId: playlistId,
    limit: _dashboardLimit,
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
      ItemFields.childcount,
    ],
  );
  final items = itemsResponse.body?.items ?? const <ItemBaseModel>[];
  if (items.isEmpty) return OxWatchlistDashboardData.empty;

  return OxWatchlistDashboardData(playlistId: playlistId, items: items);
}
