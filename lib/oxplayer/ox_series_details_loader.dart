import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/oxplayer/ox_virtual_episode_images.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:http/http.dart' as http;

/// Series catalog: seasons + all episodes in parallel (two HTTP calls).
class OxSeriesCatalogLoad {
  const OxSeriesCatalogLoad({
    required this.seasons,
    required this.episodeItems,
  });

  final Response<BaseItemDtoQueryResult?> seasons;
  final List<dto.BaseItemDto> episodeItems;
}

List<ItemFields> _oxSeriesEpisodeListFields() {
  return oxEpisodeListFields([
    ItemFields.mediastreams,
    ItemFields.mediasources,
    ItemFields.overview,
    ItemFields.candownload,
  ]);
}

Future<OxSeriesCatalogLoad> oxFetchSeriesCatalogBySeason(JellyService api, String seriesId) async {
  final fields = _oxSeriesEpisodeListFields();
  final results = await Future.wait([
    api.showsSeriesIdSeasonsGet(
      seriesId: seriesId,
      enableUserData: false,
    ),
    api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      enableUserData: true,
      fields: fields,
    ),
  ]);

  final seasons = results[0];
  final episodes = results[1];
  return OxSeriesCatalogLoad(
    seasons: seasons,
    episodeItems: episodes.body?.items ?? const [],
  );
}

/// Legacy wrapper — prefer [oxFetchSeriesCatalogBySeason].
Future<
    ({
      Response<BaseItemDtoQueryResult?> seasons,
      Response<BaseItemDtoQueryResult?> episodes,
    })> oxFetchSeriesSeasonsAndEpisodes(
  JellyService api,
  String seriesId,
) async {
  final load = await oxFetchSeriesCatalogBySeason(api, seriesId);
  return (
    seasons: load.seasons,
    episodes: Response<BaseItemDtoQueryResult?>(
      http.Response('', 200),
      BaseItemDtoQueryResult(
        items: load.episodeItems,
        totalRecordCount: load.episodeItems.length,
      ),
    ),
  );
}
