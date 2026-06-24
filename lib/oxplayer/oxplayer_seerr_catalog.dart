import 'package:fladder/models/seerr/seerr_dashboard_model.dart';

/// True when OX catalog enrich linked this TMDB hit to a playable Jellyfin item.
bool oxplayerSeerrPosterInCatalog(SeerrDashboardPosterModel poster) {
  final jellyfinId = poster.jellyfinItemId?.trim();
  if (jellyfinId != null && jellyfinId.isNotEmpty) return true;

  return poster.mediaStatus == SeerrMediaStatus.available ||
      poster.mediaStatus == SeerrMediaStatus.partiallyAvailable;
}

({List<SeerrDashboardPosterModel> inCatalog, List<SeerrDashboardPosterModel> rest})
    oxplayerPartitionSeerrSearchResults(List<SeerrDashboardPosterModel> results) {
  final inCatalog = <SeerrDashboardPosterModel>[];
  final rest = <SeerrDashboardPosterModel>[];
  for (final poster in results) {
    if (oxplayerSeerrPosterInCatalog(poster)) {
      inCatalog.add(poster);
    } else {
      rest.add(poster);
    }
  }
  return (inCatalog: inCatalog, rest: rest);
}
