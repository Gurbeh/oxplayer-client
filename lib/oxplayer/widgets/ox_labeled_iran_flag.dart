import 'package:flutter/material.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/playback/ox_persian_language.dart';
import 'package:fladder/oxplayer/widgets/ox_iran_flag_icon.dart';

/// Title row with optional Iran flag image (subtitle lists, detail stream pickers).
class OxLabeledIranFlag extends StatelessWidget {
  final String label;
  final String? subtitleLanguage;
  final PlaybackModel? playbackModel;
  final MediaStreamsModel? mediaStreams;
  final int subtitleIndex;
  final TextStyle? style;
  final int maxLines;
  final bool? showFlag;

  const OxLabeledIranFlag({
    required this.label,
    this.subtitleLanguage,
    this.playbackModel,
    this.mediaStreams,
    this.subtitleIndex = 0,
    this.style,
    this.maxLines = 1,
    this.showFlag,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final show = showFlag ??
        (OxplayerConfig.isEnabled &&
            OxPersianLanguage.showIranFlagForSubtitle(
              subtitleLanguage: subtitleLanguage,
              playbackModel: playbackModel,
              mediaStreams: mediaStreams,
              subtitleIndex: subtitleIndex,
            ));

    if (!show) {
      return Text(label, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OxIranFlagIcon(size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
