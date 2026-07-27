import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_episode_actions.dart';
import 'package:fladder/oxplayer/widgets/ox_series_episode_picker_sheet.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

class OxSeriesEpisodePickerButton extends ConsumerWidget {
  final SeriesModel series;
  final VoidCallback? onEpisodePlayed;

  const OxSeriesEpisodePickerButton({
    required this.series,
    this.onEpisodePlayed,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = oxSeriesPickerSeasons(series);
    if (seasons.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final label = context.localized.watch;
    final radius = BorderRadius.circular(16);

    return AnimatedFadeSize(
      duration: const Duration(milliseconds: 250),
      child: PositionProvider(
        position: PositionContext.first,
        child: FocusButton(
          onTap: () => _openPicker(context),
          autoFocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
          borderRadius: radius,
          darkOverlay: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    IconsaxPlusBold.play,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showBottomSheetPill(
      context: context,
      item: series,
      content: (context, scrollController) => OxSeriesEpisodePickerSheet(
        series: series,
        scrollController: scrollController,
        onEpisodePlayed: onEpisodePlayed,
      ),
    );
  }
}
