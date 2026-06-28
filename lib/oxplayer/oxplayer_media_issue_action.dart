import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/models/ox_media_issue_target.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_media_streams.dart';
import 'package:fladder/oxplayer/widgets/ox_media_issue_sheet.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

bool oxplayerCanReportMediaIssue(WidgetRef ref, ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled) return false;
  final user = ref.read(userProvider);
  final creds = user?.seerrCredentials;
  if (creds?.useProxy != true || creds?.isConfigured != true) return false;
  if ((user?.credentials.token ?? '').trim().isEmpty) return false;

  return switch (item) {
    MovieModel movie => oxMovieHasPlayableMedia(movie) && movie.tmdbId != null,
    EpisodeModel episode => episode.playAble && OxMediaIssueTarget.fromItem(ref, episode) != null,
    _ => false,
  };
}

List<ItemAction> oxplayerMediaIssueActions(
  BuildContext context,
  WidgetRef ref,
  ItemBaseModel item,
) {
  if (!oxplayerCanReportMediaIssue(ref, item)) return const [];

  return [
    ItemActionButton(
      icon: const Icon(IconsaxPlusLinear.flag),
      label: Text(context.localized.oxplayerReportIssue),
      action: () async {
        final target = OxMediaIssueTarget.fromItem(ref, item);
        if (target == null || !context.mounted) return;
        await showOxMediaIssueSheet(context: context, target: target);
      },
    ),
  ];
}
