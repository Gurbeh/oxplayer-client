import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_share.dart';
import 'package:fladder/oxplayer/oxplayer_share_deep_link.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';

/// Holds a deep-link destination until the user finishes OX login.
final oxplayerPendingRouteProvider = StateProvider<String?>((ref) => null);

String? _bufferedPendingPath;

bool get oxplayerHasBufferedPendingPath =>
    _bufferedPendingPath != null && _bufferedPendingPath!.isNotEmpty;

/// Called from [deepLinkBuilder] before auth is available (no [WidgetRef]).
void oxplayerBufferPendingPath(String path) {
  if (!OxplayerConfig.isEnabled) return;
  if (path.isEmpty || path == '/' || path.startsWith('/splash') || path.startsWith('/ox-login')) {
    return;
  }
  _bufferedPendingPath = path;
}

void oxplayerFlushBufferedPendingPath(WidgetRef ref) {
  final path = _bufferedPendingPath;
  if (path == null) return;
  _bufferedPendingPath = null;
  ref.read(oxplayerPendingRouteProvider.notifier).state = path;
  oxplayerFlushBufferedShareMediaSource(ref);
}

void oxplayerSetPendingRoute(WidgetRef ref, String path) {
  if (!OxplayerConfig.isEnabled) return;
  if (path.isEmpty || path == '/' || path.startsWith('/splash') || path.startsWith('/ox-login')) {
    return;
  }
  ref.read(oxplayerPendingRouteProvider.notifier).state = path;
}

/// Post-login navigation: pending deep link or dashboard.
Future<void> oxplayerNavigateAfterLogin(BuildContext context, WidgetRef ref) async {
  if (OxplayerEnv.isEnabled) {
    await oxplayerConfigureSeerrFromServer(ref);
  }
  ref.read(lockScreenActiveProvider.notifier).update((state) => false);
  if (!context.mounted) return;

  final pending = OxplayerEnv.isEnabled ? ref.read(oxplayerPendingRouteProvider) : null;
  if ((pending != null && pending.isNotEmpty) || oxplayerHasBufferedPendingPath) {
    await oxplayerReconcilePendingShareNavigation(context, ref, force: true);
    return;
  }

  await context.router.replaceAll([const DashboardRoute()]);
}
