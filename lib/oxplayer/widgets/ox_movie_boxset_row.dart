import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/ox_movie_boxset_siblings.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/localization_helper.dart';

class OxMovieBoxSetRow extends ConsumerWidget {
  final String itemId;
  final EdgeInsets contentPadding;

  const OxMovieBoxSetRow({
    required this.itemId,
    required this.contentPadding,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSiblings = ref.watch(oxMovieBoxSetSiblingsProvider(itemId));
    return asyncSiblings.when(
      data: (siblings) {
        if (siblings.isEmpty) return const SizedBox.shrink();
        return PosterRow(
          posters: siblings,
          contentPadding: contentPadding,
          label: context.localized.mediaTypeBoxset(siblings.length),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
