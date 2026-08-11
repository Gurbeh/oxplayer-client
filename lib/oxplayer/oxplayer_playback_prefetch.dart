import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_info_polling.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Warms PlaybackInfo + CDN byte ranges before the user taps Play.
abstract final class OxplayerPlaybackPrefetch {
  static const _dedupeTtl = Duration(seconds: 60);
  static final Map<String, DateTime> _recent = {};
  static final Map<String, Future<void>> _inFlight = {};

  /// Fire-and-forget when detail screen knows the likely play target.
  static void scheduleForSeries(OxplayerRead read, SeriesModel? series) {
    if (!OxplayerConfig.isEnabled || series == null) return;
    final episode = oxSeriesPlayableNextUp(series);
    if (episode == null) return;
    scheduleForItem(
      read,
      episode.id,
      startPosition: episode.userData.playBackPosition,
      mediaSourceId: episode.streamModel?.currentVersionStream?.id,
    );
  }

  static void scheduleForMovie(OxplayerRead read, MovieModel? movie) {
    if (!OxplayerConfig.isEnabled || movie == null) return;
    scheduleForItem(
      read,
      movie.id,
      startPosition: movie.userData.playBackPosition,
      mediaSourceId: movie.streamModel?.currentVersionStream?.id,
    );
  }

  /// Detail prefetch + immediate re-fire on Play tap (deduped).
  static void scheduleForItem(
    OxplayerRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
  }) {
    if (!OxplayerConfig.isEnabled || itemId.isEmpty || kIsWeb) return;
    final key = _cacheKey(itemId, startPosition, mediaSourceId);
    final last = _recent[key];
    if (last != null && DateTime.now().difference(last) < _dedupeTtl) return;
    if (_inFlight.containsKey(key)) return;

    _inFlight[key] = _run(read, itemId, startPosition: startPosition, mediaSourceId: mediaSourceId)
        .whenComplete(() => _inFlight.remove(key));
    unawaited(_inFlight[key]);
  }

  static String _cacheKey(String itemId, Duration? start, String? mediaSourceId) {
    final ticks = start?.inMilliseconds ?? 0;
    final ms = mediaSourceId?.trim() ?? '';
    return '$itemId|$ticks|$ms';
  }

  static Future<void> _run(
    OxplayerRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
  }) async {
    final key = _cacheKey(itemId, startPosition, mediaSourceId);
    final userId = read(userProvider)?.id;
    if (userId == null || userId.isEmpty) return;

    final sw = Stopwatch()..start();
    try {
      final api = read(jellyApiProvider);
      // The call itself is the warm-up — it triggers the backend's synchronous public-copy
      // hydrate (tryInlinePublicProviderCopy) so a play tap right after has a ready t.me link.
      await oxplayerPollPlaybackInfoUntilReady(() {
        return api.itemsItemIdPlaybackInfoPost(
          itemId: itemId,
          body: PlaybackInfoDto(
            userId: userId,
            startTimeTicks: startPosition?.toRuntimeTicks,
            mediaSourceId: mediaSourceId,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            autoOpenLiveStream: true,
          ),
        );
      });

      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'playbackInfoMs': sw.elapsedMilliseconds,
      });

      _recent[key] = DateTime.now();
    } catch (e) {
      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'error': e.runtimeType.toString(),
        'elapsedMs': sw.elapsedMilliseconds,
      });
    }
  }
}
