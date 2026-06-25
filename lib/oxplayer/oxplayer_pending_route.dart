import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';

/// Holds a deep-link destination until the user finishes OX login.
final oxplayerPendingRouteProvider = StateProvider<String?>((ref) => null);

String? _bufferedPendingPath;

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
  if (pending != null && pending.isNotEmpty) {
    ref.read(oxplayerPendingRouteProvider.notifier).state = null;
    await context.router.replaceAll([const HomeRoute()]);
    if (context.mounted) {
      await context.router.navigatePath(pending);
    }
    return;
  }

  await context.router.replaceAll([const DashboardRoute()]);
}
