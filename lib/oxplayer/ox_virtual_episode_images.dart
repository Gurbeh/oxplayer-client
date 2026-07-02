import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/image_provider.dart';

const _tmdbPrimaryExternalName = 'TmdbImagePrimary';

/// Extra Jellyfin fields needed for OX virtual-episode still art.
List<ItemFields> oxEpisodeListFields(List<ItemFields> base) {
  if (!OxplayerConfig.isEnabled) return base;
  return {
    ...base,
    ItemFields.externalurls,
    ItemFields.parentid,
  }.toList();
}

/// Virtual / missing episodes: TMDB still via ExternalUrls, else /Items/{id}/Images/Primary.
List<EpisodeModel> oxApplyVirtualEpisodeImages(
  List<EpisodeModel> episodes,
  List<dto.BaseItemDto>? items,
  Ref ref,
) {
  if (!OxplayerConfig.isEnabled || items == null || items.isEmpty) {
    return episodes;
  }
  final dtoById = <String, dto.BaseItemDto>{
    for (final item in items)
      if (item.id != null) item.id!: item,
  };
  return episodes
      .map((episode) => _applyStillFromDto(episode, dtoById[episode.id], ref))
      .toList();
}

EpisodeModel _applyStillFromDto(
  EpisodeModel episode,
  dto.BaseItemDto? item,
  Ref ref,
) {
  if (item == null || episode.status == EpisodeStatus.available) {
    return episode;
  }
  final still = _episodeStillImage(item, ref);
  if (still == null) return episode;
  return episode.copyWith(images: ImagesData(primary: still));
}

ImageData? _episodeStillImage(dto.BaseItemDto item, Ref ref) {
  final external = _tmdbStillUrlFromDto(item);
  if (external != null) {
    return ImageData(
      path: external,
      key: '${item.id}_ox_ext_$external',
      hash: '',
    );
  }

  final tag = item.imageTags?['Primary']?.toString();
  final id = item.id;
  if (tag != null && tag.isNotEmpty && id != null) {
    final path = ref.read(imageUtilityProvider).getItemsImageUrl(
          id,
          maxWidth: 600,
          maxHeight: 340,
        );
    if (path.isNotEmpty) {
      return ImageData(
        path: path,
        key: '${id}_ox_srv_$tag',
        hash: '',
      );
    }
  }
  return null;
}

String? _tmdbStillUrlFromDto(dto.BaseItemDto item) {
  for (final ext in item.externalUrls ?? const <dto.ExternalUrl>[]) {
    if (ext.name == _tmdbPrimaryExternalName) {
      final url = ext.url?.trim();
      if (url != null && url.startsWith('http')) return url;
    }
  }
  return null;
}
