import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// OX default search: TMDB-wide Seerr search when the server enabled Seerr proxy.
PageRouteInfo oxplayerDefaultSearchRoute({required bool seerrConfigured}) {
  if (OxplayerConfig.isEnabled && seerrConfigured) {
    return SeerrSearchRoute(mode: SeerrSearchMode.search);
  }
  return LibrarySearchRoute();
}

void oxplayerNavigateToSearch(
  BuildContext context, {
  required bool seerrConfigured,
}) {
  context.router.navigate(oxplayerDefaultSearchRoute(seerrConfigured: seerrConfigured));
}
