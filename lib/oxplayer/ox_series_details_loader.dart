import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/oxplayer/ox_virtual_episode_images.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:http/http.dart' as http;

/// Jellyfin-style series catalog load: seasons first, then parallel per-season episode lists.
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
  final seasons = await api.showsSeriesIdSeasonsGet(
    seriesId: seriesId,
    enableUserData: false,
  );
  final seasonItems = seasons.body?.items ?? const <dto.BaseItemDto>[];
  if (seasonItems.isEmpty) {
    return OxSeriesCatalogLoad(seasons: seasons, episodeItems: const []);
  }

  final fields = _oxSeriesEpisodeListFields();
  final episodeResponses = await Future.wait(
    seasonItems.map((season) {
      final seasonId = season.id?.trim();
      if (seasonId == null || seasonId.isEmpty) {
        return Future<Response<BaseItemDtoQueryResult?>>.value(
          Response<BaseItemDtoQueryResult?>(
            http.Response('', 200),
            BaseItemDtoQueryResult(items: const [], totalRecordCount: 0),
          ),
        );
      }
      return api.showsSeriesIdEpisodesGet(
        seriesId: seriesId,
        seasonId: seasonId,
        enableUserData: true,
        fields: fields,
      );
    }),
  );

  final episodeItems = <dto.BaseItemDto>[];
  for (final response in episodeResponses) {
    episodeItems.addAll(response.body?.items ?? const []);
  }
  return OxSeriesCatalogLoad(seasons: seasons, episodeItems: episodeItems);
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
