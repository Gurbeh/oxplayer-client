import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';

/// OX home refresh: one batched Home/Feed request (parallel server-side queries).
abstract final class OxplayerHomeRefresh {
  /// Refetch home data without clearing visible shelves or showing skeletons.
  static Future<void> refresh(WidgetRef ref) async {
    await ref.read(userProvider.notifier).updateInformation();
    await ref.read(viewsProvider.notifier).fetchViews(background: true);
  }
}
