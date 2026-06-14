import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/oxplayer/providers/ox_movie_seerr_request.dart';
import 'package:fladder/screens/seerr/widgets/seerr_request_popup.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

class OxMovieRequestButton extends ConsumerWidget {
  final int tmdbId;
  final bool prominent;

  const OxMovieRequestButton({
    required this.tmdbId,
    this.prominent = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncState = ref.watch(oxMovieSeerrRequestProvider(tmdbId));

    return asyncState.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) {
        if (state == null || !state.canShowRequest) {
          return const SizedBox.shrink();
        }

        if (prominent) {
          return _ProminentRequestButton(
            label: context.localized.request,
            onPressed: () => openSeerrRequestPopup(context, state.poster),
          );
        }

        return SelectableIconButton(
          onPressed: () => openSeerrRequestPopup(context, state.poster),
          selected: false,
          refreshOnEnd: false,
          icon: IconsaxPlusLinear.add,
          label: context.localized.request,
        );
      },
    );
  }
}

class _ProminentRequestButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ProminentRequestButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(16);

    return AnimatedFadeSize(
      duration: const Duration(milliseconds: 250),
      child: FocusButton(
        onTap: onPressed,
        autoFocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
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
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  IconsaxPlusBold.add,
                  color: theme.colorScheme.onPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
