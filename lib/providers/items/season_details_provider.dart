import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/oxplayer/ox_virtual_episode_images.dart';
import 'package:fladder/oxplayer/ox_season_user_data.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:logging/logging.dart' as logging;

final seasonDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeasonDetailsNotifier, SeasonModel?, String>((ref, id) {
  return SeasonDetailsNotifier(ref);
});

class SeasonDetailsNotifier extends StateNotifier<SeasonModel?> {
  SeasonDetailsNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<Response?> fetchDetails(String seasonId) async {
    SeasonModel? newState;

    final season = await api.usersUserIdItemsItemIdGet(itemId: seasonId);
    if (season.body != null) newState = season.bodyOrThrow as SeasonModel;

    final episodes = await api.showsSeriesIdEpisodesGet(
      seriesId: newState?.seriesId ?? "",
      seasonId: newState?.id,
      season: newState?.season,
      enableUserData: true,
      fields: oxEpisodeListFields([
        ItemFields.overview,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.parentid,
      ]),
    );

    List<BaseItemDto> specialFeatures;
    try {
      specialFeatures = (await api.itemsItemIdSpecialFeaturesGet(itemId: seasonId)).body ?? [];
    } on Exception catch (e, s) {
      specialFeatures = [];
      log("Failed to get special features for season id $seasonId due to $e",
          level: logging.Level.WARNING.value, error: e, stackTrace: s);
    }

    newState = newState?.copyWith(
        episodes: oxApplyVirtualEpisodeImages(
          EpisodeModel.episodesFromDto(episodes.body?.items, ref).toList(),
          episodes.body?.items,
          ref,
        ),
        specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeatures, ref).toList());
    if (OxplayerConfig.isEnabled && newState != null) {
      newState = newState.copyWith(
        userData: oxSeasonUserDataFromEpisodes(newState.episodes),
      );
    }
    state = newState;
    return season;
  }
}
