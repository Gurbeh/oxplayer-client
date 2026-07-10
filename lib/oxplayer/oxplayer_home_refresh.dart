import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/views_provider.dart';

/// OX home refresh: batched feed, no blocking user sync.
abstract final class OxplayerHomeRefresh {
  static Future<void> refresh(WidgetRef ref) async {
    unawaited(ref.read(userProvider.notifier).updateInformation());
    await ref.read(viewsProvider.notifier).fetchViews();
  }
}
