import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_media_streams.dart';
import 'package:fladder/oxplayer/widgets/ox_enum_box.dart';
import 'package:fladder/screens/details_screens/components/label_title_item.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/enum_selection.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

class MediaStreamHelper {
  final MediaStreamsModel mediaStream;
  final Function(MediaStreamsModel changed)? onItemChanged;
  MediaStreamHelper({
    required this.mediaStream,
    this.onItemChanged,
  });
}

class MediaStreamInformation extends ConsumerWidget {
  final MediaStreamsModel mediaStream;
  final Function(int index)? onVersionIndexChanged;
  final Function(int index)? onAudioIndexChanged;
  final Function(int index)? onSubIndexChanged;
  const MediaStreamInformation({
    required this.mediaStream,
    required this.onVersionIndexChanged,
    this.onAudioIndexChanged,
    this.onSubIndexChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (oxplayerShowVersionStreamPicker(mediaStream))
          _StreamOptionSelect(
            label: Text(context.localized.version),
            current: mediaStream.currentVersionStream != null
                ? oxplayerVersionStreamLabel(
                    mediaStream.currentVersionStream!,
                    l10n: context.localized,
                  )
                : '',
            interactiveWithSingleItem: OxplayerConfig.isEnabled,
            itemBuilder: (context) => mediaStream.versionStreams
                .map((e) => ItemActionButton(
                      selected: mediaStream.currentVersionStream == e,
                      label: textWidget(
                        context,
                        label: oxplayerVersionStreamLabel(e, l10n: context.localized),
                      ),
                      action: () => onVersionIndexChanged?.call(e.index),
                    ))
                .toList(),
          ),
        if (mediaStream.videoStreams.isNotEmpty)
          _StreamOptionSelect(
            label: Text(context.localized.video(1)),
            current: (mediaStream.videoStreams.first).prettyName,
            itemBuilder: (context) => mediaStream.videoStreams
                .map(
                  (e) => ItemActionButton(
                    label: Text(e.prettyName),
                  ),
                )
                .toList(),
          ),
        if (mediaStream.audioStreams.isNotEmpty)
          _StreamOptionSelect(
            label: Text(context.localized.audio(1)),
            current: mediaStream.currentAudioStream?.displayTitle ?? "",
            itemBuilder: (context) => [AudioStreamModel.no(), ...mediaStream.audioStreams]
                .map(
                  (e) => ItemActionButton(
                    selected: mediaStream.currentAudioStream?.index == e.index,
                    label: textWidget(
                      context,
                      label: e.displayTitle,
                    ),
                    action: () => onAudioIndexChanged?.call(e.index),
                  ),
                )
                .toList(),
          ),
        if (mediaStream.subStreams.isNotEmpty)
          _StreamOptionSelect(
            label: Text(context.localized.subtitles),
            current: mediaStream.currentSubStream?.displayTitle ?? "",
            itemBuilder: (context) => [SubStreamModel.no(), ...mediaStream.subStreams]
                .map(
                  (e) => ItemActionButton(
                    selected: mediaStream.currentSubStream?.index == e.index,
                    label: textWidget(
                      context,
                      label: e.displayTitle,
                    ),
                    action: () => onSubIndexChanged?.call(e.index),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget textWidget(BuildContext context, {required String label}) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

class _StreamOptionSelect<T> extends StatelessWidget {
  final Text label;
  final String current;
  final bool interactiveWithSingleItem;
  final List<ItemAction> Function(BuildContext context) itemBuilder;
  const _StreamOptionSelect({
    required this.label,
    required this.current,
    this.interactiveWithSingleItem = false,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final picker = interactiveWithSingleItem
        ? OxEnumBox(
            current: current,
            itemBuilder: itemBuilder,
          )
        : EnumBox(
            current: current,
            itemBuilder: itemBuilder,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LabelTitleItem(
        title: label,
        content: Flexible(child: picker),
      ),
    );
  }
}
