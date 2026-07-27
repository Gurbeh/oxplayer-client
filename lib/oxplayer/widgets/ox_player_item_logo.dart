import 'package:flutter/material.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/screens/shared/media/components/item_logo.dart';
import 'package:fladder/util/localization_helper.dart';

/// Player header — series logo/name plus season/episode when playing an episode.
class OxPlayerItemLogo extends StatelessWidget {
  final ItemBaseModel item;
  final Alignment imageAlignment;
  final TextStyle? textStyle;

  const OxPlayerItemLogo({
    required this.item,
    this.imageAlignment = Alignment.bottomCenter,
    this.textStyle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final logo = ItemLogo(
      item: item,
      imageAlignment: imageAlignment,
      textStyle: textStyle,
    );

    if (!OxplayerConfig.isEnabled || item is! EpisodeModel) {
      return logo;
    }

    final episode = item as EpisodeModel;
    final l10n = context.localized;
    final seasonEpisode = episode.seasonEpisodeLabelFull(l10n);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        logo,
        const SizedBox(height: 6),
        Text(
          seasonEpisode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.92),
            fontWeight: FontWeight.w700,
          ),
        ),
        if (episode.name.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            episode.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ],
    );
  }
}
