import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/refresh_after_watch_state.dart';

/// Mark season watched/unwatched and refetch season + parent series detail state.
Future<void> oxSeasonMarkPlayed(WidgetRef ref, SeasonModel season, bool played) async {
  await ref.read(userProvider.notifier).markAsPlayed(played, season.id);
  await refreshAfterWatchStateChange(ref, season);
}
