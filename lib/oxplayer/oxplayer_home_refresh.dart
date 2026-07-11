import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/oxplayer/providers/ox_watchlist_dashboard.dart';

/// OX home refresh: one batched Home/Feed request (parallel server-side queries).
abstract final class OxplayerHomeRefresh {
  static Future<void> refresh(WidgetRef ref) async {
    unawaited(ref.read(userProvider.notifier).updateInformation());
    oxResetWatchlistHomeFeed(ref);
    ref.invalidate(oxWatchlistDashboardProvider);
    await ref.read(viewsProvider.notifier).fetchViews();
  }
}
