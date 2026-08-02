import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/models/ox_media_issue_target.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

part 'ox_media_issue_context.g.dart';

class OxMediaIssueContext {
  final int seerrMediaId;
  final String title;
  final String? posterPath;

  const OxMediaIssueContext({
    required this.seerrMediaId,
    required this.title,
    this.posterPath,
  });
}

@riverpod
Future<OxMediaIssueContext> oxMediaIssueContext(
  OxMediaIssueContextRef ref,
  OxMediaIssueTarget target,
) async {
  if (!OxplayerConfig.isEnabled) {
    throw StateError('OXPlayer is disabled');
  }

  if (ref.read(userProvider)?.seerrCredentials?.isConfigured != true) {
    throw StateError('Seerr is not configured');
  }

  final api = ref.watch(seerrApiProvider);
  final int? mediaId;
  final String title;
  final String? posterPath;

  if (target.isTv) {
    final response = await api.tvDetails(tvId: target.tmdbId);
    if (!response.isSuccessful || response.body == null) {
      throw StateError('Could not load series details');
    }
    final details = response.body!;
    mediaId = details.mediaInfo?.id;
    title = details.name ?? target.displayTitle;
    posterPath = details.internalPosterPath;
  } else {
    final response = await api.movieDetails(tmdbId: target.tmdbId);
    if (!response.isSuccessful || response.body == null) {
      throw StateError('Could not load movie details');
    }
    final details = response.body!;
    mediaId = details.mediaInfo?.id;
    title = details.title ?? target.displayTitle;
    posterPath = details.internalPosterPath;
  }

  if (mediaId == null || mediaId <= 0) {
    throw StateError('Title is not linked in the request catalog yet');
  }

  return OxMediaIssueContext(
    seerrMediaId: mediaId,
    title: title,
    posterPath: posterPath,
  );
}
