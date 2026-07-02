import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_season_seerr_request.dart';
import 'package:fladder/screens/seerr/widgets/seerr_request_popup.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class OxSeasonRequestButton extends ConsumerWidget {
  final String seriesId;
  final int seasonNumber;

  const OxSeasonRequestButton({
    required this.seriesId,
    required this.seasonNumber,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerEnv.isEnabled) return const SizedBox.shrink();

    final asyncState = ref.watch(oxSeasonSeerrRequestProvider((seriesId: seriesId, seasonNumber: seasonNumber)));

    return asyncState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) {
        if (state == null || !state.canShowRequest) {
          return const SizedBox.shrink();
        }

        return SelectableIconButton(
          onPressed: () => openSeerrRequestPopup(context, state.poster),
          selected: false,
          refreshOnEnd: false,
          icon: IconsaxPlusLinear.add,
          label: context.localized.requestMore,
        );
      },
    );
  }
}
