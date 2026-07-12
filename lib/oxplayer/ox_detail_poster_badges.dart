import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/status_card.dart';

bool oxDetailPosterBadgesEnabled(bool oxDetailBadges) =>
    oxDetailBadges && OxplayerConfig.isEnabled;

Widget? oxRelatedMediaTypeBadge(BuildContext context, ItemBaseModel poster) {
  final label = switch (poster) {
    MovieModel() => context.localized.mediaTypeMovie(1),
    SeriesModel() => context.localized.mediaTypeSeries(1),
    _ => switch (poster.jellyType) {
        BaseItemKind.movie => context.localized.mediaTypeMovie(1),
        BaseItemKind.series => context.localized.mediaTypeSeries(1),
        _ => null,
      },
  };
  if (label == null) return null;

  return Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: _typeChip(context, label),
    ),
  );
}
List<Widget> oxDetailSeerrPosterOverlays(
  BuildContext context,
  SeerrDashboardPosterModel poster,
) {
  final overlays = <Widget>[
    Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: _typeChip(
          context,
          poster.type == SeerrMediaType.movie
              ? context.localized.mediaTypeMovie(1)
              : context.localized.mediaTypeSeries(1),
        ),
      ),
    ),
  ];

  final topRight = switch (poster.type) {
    SeerrMediaType.tvshow when poster.catalogChildCount != null && poster.catalogChildCount! > 0 =>
      _seriesEpisodeCountBadge(context, poster),
    _ => _seerrAvailabilityBadge(poster),
  };
  if (topRight != null) {
    overlays.add(
      Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: topRight,
        ),
      ),
    );
  }

  return overlays;
}

Widget? _seriesEpisodeCountBadge(BuildContext context, SeerrDashboardPosterModel poster) {
  final total = poster.catalogChildCount ?? 0;
  final unplayed = poster.catalogUnplayedCount;

  if (total <= 0 && (unplayed ?? 0) <= 0) {
    return _seerrAvailabilityBadge(poster);
  }

  if (unplayed == 0 && total > 0) {
    return StatusCard(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.check_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  final display = (unplayed ?? 0) > 0 ? unplayed! : total;
  return StatusCard(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        '$display',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    ),
  );
}

Widget? _seerrAvailabilityBadge(SeerrDashboardPosterModel poster) {
  final inCatalog = poster.jellyfinItemId?.trim().isNotEmpty == true;
  if (inCatalog ||
      poster.mediaStatus == SeerrMediaStatus.available ||
      poster.mediaStatus == SeerrMediaStatus.partiallyAvailable) {
    return _availabilityIconBadge(
      color: Colors.green.shade700,
      icon: IconsaxPlusLinear.import_3,
    );
  }

  if (poster.requestStatus?.isKnown == true || poster.mediaStatus.isKnown) {
    return _availabilityIconBadge(
      color: poster.displayStatusColor,
      icon: poster.mediaStatus == SeerrMediaStatus.available
          ? IconsaxPlusLinear.import_3
          : Icons.remove_rounded,
    );
  }

  return _availabilityIconBadge(
    color: Colors.red.shade700,
    icon: Icons.remove_rounded,
  );
}

Widget _typeChip(BuildContext context, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
    ),
  );
}

Widget _availabilityIconBadge({
  required Color color,
  required IconData icon,
}) {
  return Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Icon(icon, size: 18, color: Colors.white),
    ),
  );
}
