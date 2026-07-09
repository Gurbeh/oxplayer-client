import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/home_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_screen_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';

final dashboardProvider = StateNotifierProvider<DashboardNotifier, HomeModel>((ref) {
  return DashboardNotifier(ref);
});

class DashboardNotifier extends StateNotifier<HomeModel> {
  DashboardNotifier(this.ref) : super(HomeModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> fetchNextUpAndResume() async {
    Future<void> load() async {
      if (state.loading) return;
      state = state.copyWith(loading: true);

      final viewTypes =
          ref.read(viewsProvider.select((value) => value.dashboardViews)).map((e) => e.collectionType).toSet();
      const limit = 16;

      final imagesToFetch = {
        ImageType.logo,
        ImageType.primary,
        ImageType.backdrop,
        ImageType.banner,
      }.toList();

      final fieldsToFetch = {
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
        ItemFields.airtime,
      };

      final activeProgramsFuture = viewTypes.contains(CollectionType.livetv)
          ? _fetchActivePrograms(limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeVideoFuture = viewTypes.contains(CollectionType.movies) ||
              viewTypes.contains(CollectionType.tvshows)
          ? _fetchResumeItems(mediaTypes: [MediaType.video], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeAudioFuture = viewTypes.contains(CollectionType.music)
          ? _fetchResumeItems(mediaTypes: [MediaType.audio], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final resumeBooksFuture = viewTypes.contains(CollectionType.books)
          ? _fetchResumeItems(mediaTypes: [MediaType.book], imagesToFetch: imagesToFetch, fieldsToFetch: fieldsToFetch, limit: limit)
          : Future<List<ItemBaseModel>>.value(const []);

      final nextUpFuture = _fetchNextUp(fieldsToFetch);

      final results = await Future.wait<Object>([
        activeProgramsFuture,
        resumeVideoFuture,
        resumeAudioFuture,
        resumeBooksFuture,
        nextUpFuture,
      ]);

      state = state.copyWith(
        activePrograms: results[0] as List<ItemBaseModel>,
        resumeVideo: results[1] as List<ItemBaseModel>,
        resumeAudio: results[2] as List<ItemBaseModel>,
        resumeBooks: results[3] as List<ItemBaseModel>,
        nextUp: results[4] as List<ItemBaseModel>,
        loading: false,
        loaded: true,
      );
    }

    if (OxplayerConfig.isEnabled) {
      await OxplayerScreenTelemetry.trackLoad(screen: 'home', phase: 'dashboard', load: load);
      return;
    }
    await load();
  }

  Future<List<ItemBaseModel>> _fetchActivePrograms(int limit) async {
    var channels = (await api.liveTvChannelsGet(limit: limit))
            .body
            ?.items
            ?.map((e) => ChannelModel.fromBaseDto(e, ref))
            .toList() ??
        <ChannelModel>[];

    channels = await Future.wait(
      channels.map(
        (e) async {
          final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(e);
          return e.copyChannelWith(programs: programs);
        },
      ),
    );

    return channels;
  }

  Future<List<ItemBaseModel>> _fetchNextUp(Set<ItemFields> fieldsToFetch) async {
    final response = await api.showsNextUpGet(
      nextUpDateCutoff: DateTime.now().subtract(
        ref.read(clientSettingsProvider.select((value) => value.nextUpDateCutoff ?? const Duration(days: 28))),
      ),
      fields: fieldsToFetch.toList(),
    );

    return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? const [];
  }

  Future<List<ItemBaseModel>> _fetchResumeItems({
    required List<MediaType> mediaTypes,
    required List<ImageType> imagesToFetch,
    required Set<ItemFields> fieldsToFetch,
    required int limit,
  }) async {
    final response = await api.usersUserIdItemsResumeGet(
      enableImageTypes: imagesToFetch,
      fields: fieldsToFetch.toList(),
      mediaTypes: mediaTypes,
      enableTotalRecordCount: false,
      limit: limit,
    );

    return response.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? const [];
  }

  void clear() {
    state = HomeModel();
  }
}
