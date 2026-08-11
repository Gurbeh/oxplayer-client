import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_prefetch.dart';
import 'package:fladder/oxplayer/oxplayer_share.dart';

/// Delivery / track flavor for a file variant (soft sub, dubbed, etc.).
enum OxStreamDelivery {
  softSub,
  dubbed,
  hardSub,
  original,
  unknown,
}

/// User's last explicit version pick (persisted locally).
class OxMediaVariantPreference {
  const OxMediaVariantPreference({
    this.qualityHeight,
    this.delivery,
  });

  /// Normalized height tier: 2160, 1080, 720, …
  final int? qualityHeight;
  final OxStreamDelivery? delivery;

  bool get hasUserChoice => qualityHeight != null || delivery != null;

  static const unset = OxMediaVariantPreference();

  static const _qualityKey = 'ox_media_variant_quality_height';
  static const _deliveryKey = 'ox_media_variant_delivery';

  static Future<OxMediaVariantPreference> load(SharedPreferences prefs) async {
    final height = prefs.getInt(_qualityKey);
    final deliveryRaw = prefs.getString(_deliveryKey);
    return OxMediaVariantPreference(
      qualityHeight: height,
      delivery: deliveryRaw == null ? null : OxStreamDelivery.values.byName(deliveryRaw),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    if (qualityHeight != null) {
      await prefs.setInt(_qualityKey, qualityHeight!);
    } else {
      await prefs.remove(_qualityKey);
    }
    if (delivery != null) {
      await prefs.setString(_deliveryKey, delivery!.name);
    } else {
      await prefs.remove(_deliveryKey);
    }
  }

  OxMediaVariantPreference copyWith({
    int? qualityHeight,
    OxStreamDelivery? delivery,
    bool clearQuality = false,
    bool clearDelivery = false,
  }) {
    return OxMediaVariantPreference(
      qualityHeight: clearQuality ? null : (qualityHeight ?? this.qualityHeight),
      delivery: clearDelivery ? null : (delivery ?? this.delivery),
    );
  }
}

final oxMediaVariantPreferenceProvider =
    NotifierProvider<OxMediaVariantPreferenceNotifier, OxMediaVariantPreference>(
  OxMediaVariantPreferenceNotifier.new,
);

class OxMediaVariantPreferenceNotifier extends Notifier<OxMediaVariantPreference> {
  SharedPreferences? _prefs;

  @override
  OxMediaVariantPreference build() {
    Future.microtask(_loadFromDisk);
    return OxMediaVariantPreference.unset;
  }

  Future<void> _loadFromDisk() async {
    _prefs ??= await SharedPreferences.getInstance();
    final loaded = await OxMediaVariantPreference.load(_prefs!);
    state = loaded;
  }

  Future<void> rememberStream(VersionStreamModel stream) async {
    if (!OxplayerConfig.isEnabled) return;
    final meta = oxClassifyVersionStream(stream);
    final next = OxMediaVariantPreference(
      qualityHeight: meta.qualityHeight,
      delivery: meta.delivery == OxStreamDelivery.unknown ? null : meta.delivery,
    );
    state = next;
    _prefs ??= await SharedPreferences.getInstance();
    await next.save(_prefs!);
  }
}

class OxVersionStreamMeta {
  const OxVersionStreamMeta({
    required this.qualityHeight,
    required this.delivery,
  });

  final int? qualityHeight;
  final OxStreamDelivery delivery;
}

const _defaultQualityTiers = [1080, 720, 576, 480, 360, 2160, 1440];

OxVersionStreamMeta oxClassifyVersionStream(VersionStreamModel stream) {
  final blob = '${stream.name} ${stream.detailedResolutionLabel}'.toLowerCase();
  final delivery = _deliveryFromLabel(blob, stream);
  final qualityHeight = _qualityHeightFromLabel(blob) ?? _qualityHeightFromVideo(stream);
  return OxVersionStreamMeta(qualityHeight: qualityHeight, delivery: delivery);
}

OxStreamDelivery _deliveryFromLabel(String blob, VersionStreamModel stream) {
  if (RegExp(r'soft[\s_-]*sub').hasMatch(blob) || blob.contains('softsub')) {
    return OxStreamDelivery.softSub;
  }
  if (RegExp(r'hard[\s_-]*sub').hasMatch(blob) || blob.contains('hardsub')) {
    return OxStreamDelivery.hardSub;
  }
  if (RegExp(r'\bdub(?:bed)?\b').hasMatch(blob) || blob.contains('دوبله') || blob.contains('🎙')) {
    return OxStreamDelivery.dubbed;
  }
  if (RegExp(r'soft\s+sub').hasMatch(blob)) {
    return OxStreamDelivery.softSub;
  }
  if (RegExp(r'hard\s+sub').hasMatch(blob)) {
    return OxStreamDelivery.hardSub;
  }
  if (stream.subStreams.isNotEmpty) {
    return OxStreamDelivery.softSub;
  }
  if (blob.contains('original')) {
    return OxStreamDelivery.original;
  }
  return OxStreamDelivery.original;
}

int? _qualityHeightFromLabel(String blob) {
  final match = RegExp(r'\b(2160|1440|1080|720|576|480|360)p?\b').firstMatch(blob);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

int? _qualityHeightFromVideo(VersionStreamModel stream) {
  final height = stream.videoStreams.firstOrNull?.height;
  if (height == null || height <= 0) return null;
  return oxNormalizeQualityHeight(height);
}

int oxNormalizeQualityHeight(int height) {
  if (height >= 1900) return 2160;
  if (height >= 1200) return 1440;
  if (height >= 900) return 1080;
  if (height >= 600) return 720;
  if (height >= 510) return 576;
  if (height >= 420) return 480;
  if (height >= 330) return 360;
  return height;
}

/// Pick a [versionStreams] index using saved preference or cold-start defaults.
int oxplayerPickVersionStreamIndex(
  List<VersionStreamModel> streams,
  OxMediaVariantPreference preference,
) {
  if (streams.isEmpty) return 0;
  if (streams.length == 1) return streams.first.index;

  final classified = streams
      .map((stream) => (stream: stream, meta: oxClassifyVersionStream(stream)))
      .toList();

  if (preference.hasUserChoice) {
    return _pickWithPreference(classified, preference);
  }
  return _pickColdDefault(classified);
}

int _pickColdDefault(List<({VersionStreamModel stream, OxVersionStreamMeta meta})> classified) {
  for (final tier in const [1080, 720]) {
    final soft = classified.firstWhereOrNull(
      (e) => e.meta.qualityHeight == tier && e.meta.delivery == OxStreamDelivery.softSub,
    );
    if (soft != null) return soft.stream.index;

    final any = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (any != null) return any.stream.index;
  }

  for (final tier in _defaultQualityTiers) {
    if (tier == 1080 || tier == 720) continue;
    final match = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (match != null) return match.stream.index;
  }

  return classified.first.stream.index;
}

int _pickWithPreference(
  List<({VersionStreamModel stream, OxVersionStreamMeta meta})> classified,
  OxMediaVariantPreference preference,
) {
  final tiers = _qualityTiersToTry(preference.qualityHeight);
  final preferredDelivery = preference.delivery;

  if (preference.qualityHeight != null) {
    final tier = preference.qualityHeight!;
    for (final delivery in _deliveryFallbacks(preferredDelivery, includeOriginal: false)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    if (preferredDelivery == null) {
      final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
      if (anyAtTier != null) return anyAtTier.stream.index;
    }
  }

  for (final tier in tiers) {
    if (tier == preference.qualityHeight) continue;
    if (preferredDelivery != null) {
      final dubbedMatch = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == preferredDelivery,
      );
      if (dubbedMatch != null) return dubbedMatch.stream.index;
    }
    for (final delivery in _deliveryFallbacks(preferredDelivery)) {
      final match = classified.firstWhereOrNull(
        (e) => e.meta.qualityHeight == tier && e.meta.delivery == delivery,
      );
      if (match != null) return match.stream.index;
    }
    final anyAtTier = classified.firstWhereOrNull((e) => e.meta.qualityHeight == tier);
    if (anyAtTier != null) return anyAtTier.stream.index;
  }

  for (final delivery in _deliveryFallbacks(preferredDelivery)) {
    final match = classified.firstWhereOrNull((e) => e.meta.delivery == delivery);
    if (match != null) return match.stream.index;
  }

  return classified.first.stream.index;
}

List<int> _qualityTiersToTry(int? preferred) {
  if (preferred == null) return _defaultQualityTiers;
  final rest = _defaultQualityTiers.where((t) => t != preferred).toList();
  return [preferred, ...rest];
}

List<OxStreamDelivery> _deliveryFallbacks(
  OxStreamDelivery? preferred, {
  bool includeOriginal = true,
}) {
  const core = [
    OxStreamDelivery.softSub,
    OxStreamDelivery.dubbed,
    OxStreamDelivery.hardSub,
  ];
  final base = preferred == null
      ? core
      : [preferred, ...core.where((d) => d != preferred)];
  if (!includeOriginal) return base;
  return [...base, OxStreamDelivery.original, OxStreamDelivery.unknown];
}

MediaStreamsModel oxplayerApplyPreferredVersionStream(
  Ref ref,
  MediaStreamsModel streams,
) {
  if (!OxplayerConfig.isEnabled || streams.versionStreams.length <= 1) {
    return streams;
  }
  final pref = ref.read(oxMediaVariantPreferenceProvider);
  final idx = oxplayerPickVersionStreamIndex(streams.versionStreams, pref);
  if (idx == (streams.versionStreamIndex ?? 0)) return streams;
  return streams.copyWith(versionStreamIndex: idx);
}

void oxplayerRememberMediaStreamsSelection(WidgetRef ref, MediaStreamsModel streams) {
  if (!OxplayerConfig.isEnabled) return;
  final current = streams.currentVersionStream;
  if (current == null) return;
  ref.read(oxMediaVariantPreferenceProvider.notifier).rememberStream(current);
}

MediaStreamsModel oxplayerOnUserMediaStreamsChanged(
  WidgetRef ref,
  MediaStreamsModel changed, {
  String? itemId,
}) {
  oxplayerRememberMediaStreamsSelection(ref, changed);
  if (OxplayerConfig.isEnabled && itemId != null && itemId.isNotEmpty) {
    final msId = changed.currentVersionStream?.id;
    if (msId != null && msId.isNotEmpty) {
      OxplayerPlaybackPrefetch.scheduleForItem(ref.read, itemId, mediaSourceId: msId);
    }
  }
  return changed;
}

MovieModel? oxplayerPrepareMovieMediaStreams(MovieModel? movie, Ref ref) {
  if (movie == null || !OxplayerConfig.isEnabled) return movie;
  var item = oxplayerApplyShareMediaSourceToMovie(movie, ref) ?? movie;
  final streams = oxplayerApplyPreferredVersionStream(ref, item.mediaStreams);
  if (streams == item.mediaStreams) return item;
  return item.copyWith(mediaStreams: streams);
}

EpisodeModel? oxplayerPrepareEpisodeMediaStreams(EpisodeModel? episode, Ref ref) {
  if (episode == null || !OxplayerConfig.isEnabled) return episode;
  var item = oxplayerApplyShareMediaSourceToEpisode(episode, ref) ?? episode;
  final streams = oxplayerApplyPreferredVersionStream(ref, item.mediaStreams);
  if (streams == item.mediaStreams) return item;
  return item.copyWith(mediaStreams: streams);
}

List<EpisodeModel> oxplayerPrepareEpisodeListMediaStreams(Ref ref, List<EpisodeModel> episodes) {
  if (!OxplayerConfig.isEnabled || episodes.isEmpty) return episodes;
  return episodes
      .map((episode) => oxplayerPrepareEpisodeMediaStreams(episode, ref) ?? episode)
      .toList();
}
