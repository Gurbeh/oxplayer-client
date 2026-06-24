import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/seerr/seerr_models.dart';

int _tmdbIdFromProviderIds(Map<String, dynamic>? providerIds) {
  final tmdbRaw = providerIds?['Tmdb'] ?? providerIds?['tmdb'];
  return switch (tmdbRaw) {
    final int n => n,
    final String s => int.tryParse(s) ?? 0,
    _ => 0,
  };
}

SeerrDashboardPosterModel? oxplayerPosterFromCatalogItem(ItemBaseModel item) {
  final id = item.id.trim();
  if (id.isEmpty) return null;

  final type = switch (item) {
    MovieModel() => SeerrMediaType.movie,
    SeriesModel() => SeerrMediaType.tvshow,
    _ => switch (item.jellyType) {
        BaseItemKind.movie => SeerrMediaType.movie,
        BaseItemKind.series => SeerrMediaType.tvshow,
        _ => null,
      },
  };
  if (type == null) return null;

  final providerIds = switch (item) {
    MovieModel movie => movie.providerIds,
    SeriesModel series => series.providerIds,
    _ => null,
  };
  final releaseYear = switch (item) {
    MovieModel movie => movie.premiereDate.year.toString(),
    _ => item.overview.productionYear?.toString() ?? item.overview.yearAired?.toString(),
  };

  return SeerrDashboardPosterModel(
    id: id,
    type: type,
    tmdbId: _tmdbIdFromProviderIds(providerIds),
    jellyfinItemId: id,
    title: item.name,
    overview: item.overview.summary,
    images: item.images ?? ImagesData(),
    mediaStatus: SeerrMediaStatus.available,
    releaseYear: releaseYear,
  );
}

SeerrDashboardPosterModel? oxplayerPosterFromCatalogDto(BaseItemDto dto, Ref ref) {
  final id = dto.id?.trim() ?? '';
  if (id.isEmpty) return null;

  final kind = dto.type;
  if (kind != BaseItemKind.movie && kind != BaseItemKind.series) return null;

  final itemModel = ItemBaseModel.fromBaseDto(dto, ref);
  return oxplayerPosterFromCatalogItem(itemModel);
}
