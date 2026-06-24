import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_catalog_poster.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// Jellyfin catalog search for the Seerr "in library" filter (not TMDB subset).
final oxplayerSeerrCatalogSearchProvider =
    FutureProvider.autoDispose.family<List<SeerrDashboardPosterModel>, OxplayerSeerrCatalogSearchQuery>(
  (ref, query) => oxplayerSearchCatalogAsSeerrPosters(ref, query),
);

SeerrMediaType? oxplayerSeerrCatalogMediaTypeFilter(SeerrSearchMode mode) {
  return switch (mode) {
    SeerrSearchMode.discoverMovies => SeerrMediaType.movie,
    SeerrSearchMode.discoverTv => SeerrMediaType.tvshow,
    _ => null,
  };
}

class OxplayerSeerrCatalogSearchQuery {
  const OxplayerSeerrCatalogSearchQuery({
    required this.term,
    this.mediaType,
  });

  final String term;
  final SeerrMediaType? mediaType;

  @override
  bool operator ==(Object other) =>
      other is OxplayerSeerrCatalogSearchQuery && other.term == term && other.mediaType == mediaType;

  @override
  int get hashCode => Object.hash(term, mediaType);
}

List<BaseItemKind> _includeItemTypes(SeerrMediaType? mediaType) {
  return switch (mediaType) {
    SeerrMediaType.movie => [BaseItemKind.movie],
    SeerrMediaType.tvshow => [BaseItemKind.series],
    _ => [BaseItemKind.movie, BaseItemKind.series],
  };
}

int _catalogTitleMatchScore(String title, String term) {
  final t = term.trim().toLowerCase();
  if (t.isEmpty) return 0;
  final name = title.toLowerCase();
  if (name.startsWith(t)) return 0;
  if (RegExp('(^|[\\s\\-:._(])${RegExp.escape(t)}').hasMatch(name)) return 1;
  if (name.contains(t)) return 2;
  return 99;
}

bool _catalogTitleMatches(String title, String term) {
  return _catalogTitleMatchScore(title, term) < 99;
}

Future<List<SeerrDashboardPosterModel>> oxplayerSearchCatalogAsSeerrPosters(
  Ref ref,
  OxplayerSeerrCatalogSearchQuery query,
) async {
  final term = query.term.trim();
  if (term.isEmpty) return const [];

  final api = ref.read(jellyApiProvider);
  final includeTypes = _includeItemTypes(query.mediaType);
  const fields = [
    ItemFields.overview,
    ItemFields.originaltitle,
    ItemFields.primaryimageaspectratio,
    ItemFields.providerids,
  ];

  final posters = <SeerrDashboardPosterModel>[];
  final seenIds = <String>{};

  void addItems(Iterable<ItemBaseModel> items) {
    for (final item in items) {
      if (!_catalogTitleMatches(item.name, term)) continue;
      final poster = oxplayerPosterFromCatalogItem(item);
      if (poster != null && seenIds.add(poster.id)) {
        posters.add(poster);
      }
    }
  }

  final response = await api.itemsGet(
    searchTerm: term,
    recursive: true,
    limit: 50,
    includeItemTypes: includeTypes,
    fields: fields,
  );
  addItems(response.body?.items ?? const []);

  posters.sort((a, b) {
    final score = _catalogTitleMatchScore(a.title, term).compareTo(_catalogTitleMatchScore(b.title, term));
    if (score != 0) return score;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  return posters;
}
