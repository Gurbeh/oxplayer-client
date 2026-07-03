import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/providers/ox_tmdb_interest.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

/// Follow + favorite actions for Seerr titles not yet in the user's library.
class OxSeerrInterestButtons extends ConsumerWidget {
  final SeerrDashboardPosterModel poster;

  const OxSeerrInterestButtons({
    required this.poster,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OxplayerConfig.isEnabled || poster.jellyfinItemId != null) {
      return const SizedBox.shrink();
    }

    final provider = oxTmdbInterestProvider(poster.tmdbId, poster.type);
    final interestAsync = ref.watch(provider);
    final interest = interestAsync.value ?? const OxTmdbInterestState();
    final theme = Theme.of(context).colorScheme;
    final posterUrl = poster.images.primary?.path ?? '';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SelectableIconButton(
          refreshOnEnd: false,
          selected: interest.following,
          icon: IconsaxPlusLinear.notification,
          selectedIcon: IconsaxPlusLinear.notification_bing,
          label: interest.following ? context.localized.oxplayerUnfollow : context.localized.oxplayerFollow,
          backgroundColor: theme.tertiaryContainer,
          iconColor: theme.onTertiaryContainer,
          onPressed: () => _toggleFollow(context, ref, provider, interest.following, posterUrl),
        ),
        SelectableIconButton(
          refreshOnEnd: false,
          selected: interest.favorited,
          icon: IconsaxPlusLinear.heart_add,
          selectedIcon: IconsaxPlusBold.heart,
          label: interest.favorited ? context.localized.removeAsFavorite : context.localized.addAsFavorite,
          backgroundColor: theme.tertiaryContainer,
          iconColor: theme.onTertiaryContainer,
          onPressed: () => _toggleFavorite(context, ref, provider, interest.favorited, posterUrl),
        ),
      ],
    );
  }

  Future<void> _toggleFollow(
    BuildContext context,
    WidgetRef ref,
    OxTmdbInterestProvider provider,
    bool wasFollowing,
    String posterUrl,
  ) async {
    developer.log(
      'ox seerr follow tap tmdb=${poster.tmdbId} type=${poster.type} -> ${!wasFollowing}',
      name: 'OxSeerrInterest',
    );
    final ok = await ref.read(provider.notifier).setFollowing(
          !wasFollowing,
          title: poster.title,
          posterUrl: posterUrl,
        );
    if (!context.mounted) return;
    if (!ok) {
      FladderSnack.show(context.localized.somethingWentWrong, context: context);
      return;
    }
    final nowFollowing = ref.read(provider).value?.following ?? false;
    if (nowFollowing == wasFollowing) return;
    FladderSnack.show(
      nowFollowing ? context.localized.oxplayerFollowAdded : context.localized.oxplayerFollowRemoved,
      context: context,
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    OxTmdbInterestProvider provider,
    bool wasFavorited,
    String posterUrl,
  ) async {
    developer.log(
      'ox seerr favorite tap tmdb=${poster.tmdbId} type=${poster.type} -> ${!wasFavorited}',
      name: 'OxSeerrInterest',
    );
    final ok = await ref.read(provider.notifier).setFavorited(
          !wasFavorited,
          title: poster.title,
          posterUrl: posterUrl,
        );
    if (!context.mounted) return;
    if (!ok) {
      FladderSnack.show(context.localized.somethingWentWrong, context: context);
      return;
    }
    final nowFavorited = ref.read(provider).value?.favorited ?? false;
    if (nowFavorited == wasFavorited) return;
    FladderSnack.show(
      nowFavorited ? context.localized.addAsFavorite : context.localized.removeAsFavorite,
      context: context,
    );
  }
}
