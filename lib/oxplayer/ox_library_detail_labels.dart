import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';

/// Shared OX detail chips (Seerr ratings). Adult chip is rendered in [OverviewHeader].
List<SimpleLabel> oxLibraryDetailLabels(
  BuildContext context,
  WidgetRef ref,
  String itemId,
  OverviewModel overview, {
  String? officialRatingFallback,
}) {
  if (!OxplayerConfig.isEnabled) return const [];

  return oxSeerrRatingLabels(context, ref.watch(oxLibraryItemRatingsProvider(itemId)));
}
