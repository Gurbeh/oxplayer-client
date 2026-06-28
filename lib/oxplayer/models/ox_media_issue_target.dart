import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/providers/items/episode_details_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identifies library media for a Seerr issue report.
class OxMediaIssueTarget {
  final String mediaType;
  final int tmdbId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String displayTitle;

  const OxMediaIssueTarget({
    required this.mediaType,
    required this.tmdbId,
    required this.displayTitle,
    this.seasonNumber,
    this.episodeNumber,
  });

  @override
  bool operator ==(Object other) {
    return other is OxMediaIssueTarget &&
        other.mediaType == mediaType &&
        other.tmdbId == tmdbId &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber;
  }

  @override
  int get hashCode => Object.hash(mediaType, tmdbId, seasonNumber, episodeNumber);

  bool get isTv => mediaType == 'tv';

  String episodePrefix() {
    if (seasonNumber == null || episodeNumber == null) return '';
    return 'S${seasonNumber!}E${episodeNumber!}: ';
  }

  static OxMediaIssueTarget? fromItem(WidgetRef ref, ItemBaseModel item) {
    return switch (item) {
      MovieModel movie => _fromMovie(movie),
      EpisodeModel episode => _fromEpisode(ref, episode),
      _ => null,
    };
  }

  static OxMediaIssueTarget? _fromMovie(MovieModel movie) {
    final tmdbId = movie.tmdbId;
    if (tmdbId == null) return null;
    return OxMediaIssueTarget(
      mediaType: 'movie',
      tmdbId: tmdbId,
      displayTitle: movie.name,
    );
  }

  static OxMediaIssueTarget? _fromEpisode(WidgetRef ref, EpisodeModel episode) {
    final series = ref.read(episodeDetailsProvider(episode.id)).series;
    final tmdbId = series?.tmdbId;
    if (tmdbId == null) return null;
    final seriesTitle = series?.name ?? episode.seriesName ?? episode.name;
    return OxMediaIssueTarget(
      mediaType: 'tv',
      tmdbId: tmdbId,
      seasonNumber: episode.season,
      episodeNumber: episode.episode,
      displayTitle: seriesTitle,
    );
  }
}
