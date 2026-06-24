import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// OX default search target: Discover (Seerr) when the server enabled Seerr proxy.
PageRouteInfo oxplayerDefaultSearchRoute({required bool seerrConfigured}) {
  if (OxplayerConfig.isEnabled && seerrConfigured) {
    return const SeerrRoute();
  }
  return LibrarySearchRoute();
}

void oxplayerNavigateToSearch(
  BuildContext context, {
  required bool seerrConfigured,
}) {
  context.router.navigate(oxplayerDefaultSearchRoute(seerrConfigured: seerrConfigured));
}
