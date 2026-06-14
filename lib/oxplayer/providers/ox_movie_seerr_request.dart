import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/ox_seerr_request_visibility.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

part 'ox_movie_seerr_request.g.dart';

class OxMovieSeerrRequestState {
  final SeerrDashboardPosterModel poster;
  final bool canShowRequest;

  const OxMovieSeerrRequestState({
    required this.poster,
    required this.canShowRequest,
  });
}

@riverpod
Future<OxMovieSeerrRequestState?> oxMovieSeerrRequest(
  OxMovieSeerrRequestRef ref,
  int tmdbId,
) async {
  if (!OxplayerEnv.isEnabled) return null;

  final seerrConfigured = ref.read(userProvider)?.seerrCredentials?.isConfigured == true;
  if (!seerrConfigured) return null;

  final api = ref.read(seerrApiProvider);

  final poster = await api.fetchDashboardPosterFromIds(
    tmdbId: tmdbId,
    mediaType: SeerrMediaType.movie,
  );
  if (poster == null) return null;

  final movieDetailsResponse = await api.movieDetails(tmdbId: tmdbId);
  if (!movieDetailsResponse.isSuccessful || movieDetailsResponse.body == null) return null;

  final details = movieDetailsResponse.body!;
  final updatedPoster = poster.copyWith(
    mediaInfo: details.mediaInfo,
    mediaStatus: details.mediaInfo?.mediaStatus ?? poster.mediaStatus,
    jellyfinItemId: details.mediaInfo?.primaryJellyfinMediaId ?? poster.jellyfinItemId,
  );

  final canShowRequest = oxMovieIsRequestable(updatedPoster.mediaStatus);

  return OxMovieSeerrRequestState(
    poster: updatedPoster,
    canShowRequest: canShowRequest,
  );
}
