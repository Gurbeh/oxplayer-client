import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_info_polling.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Warms PlaybackInfo (public-provider copy) and caches the playable t.me link in-memory.
abstract final class OxplayerPlaybackPrefetch {
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

  /// Detail open / quality change / Play tap — coalesce identical in-flight only.
  /// Always refreshes the in-memory link cache when the call succeeds (process TTL = 2h).
  static void scheduleForItem(
    OxplayerRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
  }) {
    if (!OxplayerConfig.isEnabled || itemId.isEmpty || kIsWeb) return;
    final key = _cacheKey(itemId, mediaSourceId);
    if (_inFlight.containsKey(key)) return;

    _inFlight[key] = _run(read, itemId, startPosition: startPosition, mediaSourceId: mediaSourceId)
        .whenComplete(() => _inFlight.remove(key));
    unawaited(_inFlight[key]);
  }

  /// Play path: wait for an in-flight prefetch for this MediaSource before falling back to API.
  static Future<void> waitInFlightForMediaSource(String? mediaSourceId) async {
    final ms = mediaSourceId?.trim() ?? '';
    if (ms.isEmpty) return;
    final pending = _inFlight.entries
        .where((e) => e.key.endsWith('|$ms') || e.key == '|$ms')
        .map((e) => e.value)
        .toList();
    if (pending.isEmpty) return;
    await Future.wait(pending);
  }

  static String _cacheKey(String itemId, String? mediaSourceId) {
    final ms = mediaSourceId?.trim() ?? '';
    return '$itemId|$ms';
  }

  static Future<void> _run(
    OxplayerRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
  }) async {
    final userId = read(userProvider)?.id;
    if (userId == null || userId.isEmpty) return;

    final sw = Stopwatch()..start();
    try {
      final api = read(jellyApiProvider);
      final response = await oxplayerPollPlaybackInfoUntilReady(() {
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

      if (response.isSuccessful && response.body != null) {
        OxplayerPlaybackLinkCache.putFromResponse(response.body);
      }

      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'mediaSourceId': mediaSourceId,
        'cached': response.body != null,
        'playbackInfoMs': sw.elapsedMilliseconds,
      });
    } catch (e) {
      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'mediaSourceId': mediaSourceId,
        'error': e.runtimeType.toString(),
        'elapsedMs': sw.elapsedMilliseconds,
      });
    }
  }
}
