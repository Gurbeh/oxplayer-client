import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_favourites_feed.dart';

const _dashboardFavoritesLimit = 16;

class OxFavoritesDashboardData {
  const OxFavoritesDashboardData({this.items = const []});

  final List<ItemBaseModel> items;

  static const empty = OxFavoritesDashboardData();
}

/// Favorites row parsed from GET /Users/{id}/Home/Feed (no extra HTTP on home).
final oxFavoritesDashboardFeedProvider = StateProvider<OxFavoritesDashboardData?>((ref) => null);

/// True after home feed applied favorites data.
final oxFavoritesFeedHandledProvider = StateProvider<bool>((ref) => false);

void oxApplyFavoritesFromHomeFeedRef(Ref ref, OxFavoritesDashboardData data) {
  ref.read(oxFavoritesDashboardFeedProvider.notifier).state = data;
  ref.read(oxFavoritesFeedHandledProvider.notifier).state = true;
}

void oxResetFavoritesHomeFeedRef(Ref ref) {
  ref.read(oxFavoritesDashboardFeedProvider.notifier).state = null;
  ref.read(oxFavoritesFeedHandledProvider.notifier).state = false;
}

/// Fallback when Home/Feed omits Favorites (older API).
final oxFavoritesDashboardProvider = FutureProvider<OxFavoritesDashboardData>((ref) async {
  if (!OxplayerConfig.isEnabled) return OxFavoritesDashboardData.empty;

  final feed = await OxplayerFavoritesFeed.fetch(ref);
  if (feed == null) return OxFavoritesDashboardData.empty;

  final items = feed.favourites.values
      .expand((list) => list)
      .take(_dashboardFavoritesLimit)
      .toList();
  if (items.isEmpty) return OxFavoritesDashboardData.empty;
  return OxFavoritesDashboardData(items: items);
});
