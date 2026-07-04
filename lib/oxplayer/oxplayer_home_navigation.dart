import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// When opening an episode from home (Next Up / Continue Watching), land on the
/// series page so Follow, seasons, and request actions are available.
///
/// If the user is already on that series detail screen, keep Fladder behavior
/// and open the episode page (e.g. tapping another episode in the row).
Future<bool> oxplayerMaybeNavigateEpisodeToSeries(
  BuildContext context,
  EpisodeModel episode, {
  Object? tag,
}) async {
  if (!OxplayerConfig.isEnabled) return false;

  final seriesId = episode.parentId;
  if (seriesId == null || seriesId.isEmpty) return false;

  final top = context.router.topRoute;
  if (top.name == DetailsRoute.name) {
    final currentId = top.queryParams.getString('id', '');
    if (currentId == seriesId) return false;
  }

  await context.router.push(DetailsRoute(id: seriesId, tag: tag));
  return true;
}
