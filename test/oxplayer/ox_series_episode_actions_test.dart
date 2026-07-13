import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_episode_actions.dart';
import 'package:flutter_test/flutter_test.dart';
EpisodeModel _episode({required String id, required int episode}) {
  return EpisodeModel(
    seriesName: 'Show',
    season: 1,
    episode: episode,
    episodeEnd: null,
    location: ItemLocation.filesystem,
    name: 'Ep $episode',
    id: id,
    overview: const OverviewModel(),
    parentId: 'series-1',
    playlistId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    parentImages: null,
    mediaStreams: MediaStreamsModel(versionStreams: []),
  );
}

SeriesModel _series({EpisodeModel? selected, List<EpisodeModel>? episodes}) {
  return SeriesModel(
    originalTitle: '',
    sortName: '',
    status: '',
    name: 'Show',
    id: 'series-1',
    playlistId: null,
    overview: const OverviewModel(),
    parentId: null,
    images: null,
    childCount: null,
    primaryRatio: null,
    userData: const UserData(),
    selectedEpisode: selected,
    availableEpisodes: episodes,
  );
}

void main() {
  test('oxSeriesDetailPlayTarget prefers selectedEpisode over next up', () {
    final ep1 = _episode(id: 'ep-1', episode: 1);
    final ep18 = _episode(id: 'ep-18', episode: 18);
    final series = _series(
      selected: ep18,
      episodes: [ep1, ep18],
    );

    expect(oxSeriesDetailPlayTarget(series, selectedEpisode: ep18)?.id, 'ep-18');
  });

  test('oxSeriesDetailPlayTarget falls back to next up when none selected', () {
    final ep1 = _episode(id: 'ep-1', episode: 1).copyWith(
      userData: const UserData(progress: 50),
    );
    final ep18 = _episode(id: 'ep-18', episode: 18);
    final series = _series(episodes: [ep1, ep18]);

    expect(oxSeriesDetailPlayTarget(series)?.id, 'ep-1');
  });
}
