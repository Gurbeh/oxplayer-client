import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/widgets/ox_series_episode_picker_sheet.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

Future<void> oxShowSeriesEpisodePicker({
  required BuildContext context,
  required WidgetRef ref,
  required SeriesModel series,
  VoidCallback? onEpisodePlayed,
}) {
  return showBottomSheetPill(
    context: context,
    item: series,
    content: (context, scrollController) => OxSeriesEpisodePickerSheet(
      series: series,
      onEpisodePlayed: onEpisodePlayed,
    ),
  );
}
