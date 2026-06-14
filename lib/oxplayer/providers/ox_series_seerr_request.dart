import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_seerr_request_visibility.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/seerr_helpers.dart';

part 'ox_series_seerr_request.g.dart';

class OxSeriesSeerrRequestState {
  final SeerrDashboardPosterModel poster;
  final bool canShowRequest;

  const OxSeriesSeerrRequestState({
    required this.poster,
    required this.canShowRequest,
  });
}

@riverpod
Future<OxSeriesSeerrRequestState?> oxSeriesSeerrRequest(
  OxSeriesSeerrRequestRef ref,
  int tmdbId,
) async {
  if (!OxplayerEnv.isEnabled) return null;

  final seerrConfigured = ref.read(userProvider)?.seerrCredentials?.isConfigured == true;
  if (!seerrConfigured) return null;

  final api = ref.read(seerrApiProvider);

  final poster = await api.fetchDashboardPosterFromIds(
    tmdbId: tmdbId,
    mediaType: SeerrMediaType.tvshow,
  );
  if (poster == null) return null;

  final tvDetailsResponse = await api.tvDetails(tvId: tmdbId);
  if (!tvDetailsResponse.isSuccessful || tvDetailsResponse.body == null) return null;

  final details = tvDetailsResponse.body!;
  final seasonStatusMap = SeerrHelpers.buildSeasonStatusMap(details);
  final seasons = details.seasons ?? const <SeerrSeason>[];

  final updatedPoster = poster.copyWith(
    seasons: seasons,
    seasonStatuses: seasonStatusMap.isEmpty ? poster.seasonStatuses : seasonStatusMap,
    mediaInfo: details.mediaInfo,
    mediaStatus: details.mediaInfo?.mediaStatus ?? poster.mediaStatus,
    jellyfinItemId: details.mediaInfo?.primaryJellyfinMediaId ?? poster.jellyfinItemId,
  );

  final seasonStatuses = updatedPoster.seasonStatuses ?? const <int, SeerrMediaStatus>{};
  final canShowRequest = oxHasRequestableSeasons(
    seasons: seasons,
    seasonStatuses: seasonStatuses,
  );

  return OxSeriesSeerrRequestState(
    poster: updatedPoster,
    canShowRequest: canShowRequest,
  );
}
