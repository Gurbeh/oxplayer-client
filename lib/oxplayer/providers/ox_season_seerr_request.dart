import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_seerr_request_visibility.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/providers/ox_series_seerr_request.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

part 'ox_season_seerr_request.g.dart';

class OxSeasonSeerrRequestState {
  final SeerrDashboardPosterModel poster;
  final bool canShowRequest;

  const OxSeasonSeerrRequestState({
    required this.poster,
    required this.canShowRequest,
  });
}

@riverpod
Future<OxSeasonSeerrRequestState?> oxSeasonSeerrRequest(
  OxSeasonSeerrRequestRef ref,
  ({String seriesId, int seasonNumber}) args,
) async {
  if (!OxplayerEnv.isEnabled) return null;
  if (!oxIsRequestableSeasonNumber(args.seasonNumber)) return null;

  final seerrConfigured = ref.read(userProvider)?.seerrCredentials?.isConfigured == true;
  if (!seerrConfigured) return null;

  final seriesResp = await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: args.seriesId);
  final seriesBody = seriesResp.body;
  final providerIds = seriesBody is SeriesModel ? seriesBody.providerIds : null;
  final tmdbRaw = providerIds?['Tmdb'] ?? providerIds?['TMDB'];
  final tmdbId = int.tryParse(tmdbRaw?.toString() ?? '');
  if (tmdbId == null) return null;

  final seriesState = await ref.watch(oxSeriesSeerrRequestProvider(tmdbId).future);
  if (seriesState == null) return null;

  final status = seriesState.poster.seasonStatuses?[args.seasonNumber];
  final canShowRequest = !oxSeasonIsFullyAvailable(status);

  return OxSeasonSeerrRequestState(
    poster: seriesState.poster,
    canShowRequest: canShowRequest,
  );
}
