import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_info_polling.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_playback_media_source.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_url_resolver.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Warms PlaybackInfo (public-provider copy) and caches the playable t.me link in-memory.
abstract final class OxplayerPlaybackPrefetch {
  /// In-flight keyed by itemId — any mediaSourceId for same item shares one flight.
  static final Map<String, Future<void>> _inFlightByItem = {};

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

  /// Detail open / quality change / Play tap — coalesce by itemId.
  /// Always refreshes the in-memory link cache when the call succeeds (process TTL = 2h).
  static void scheduleForItem(
    OxplayerRead read,
    String itemId, {
    Duration? startPosition,
    String? mediaSourceId,
  }) {
    if (!OxplayerConfig.isEnabled || itemId.isEmpty || kIsWeb) return;
    if (_inFlightByItem.containsKey(itemId)) return;

    _inFlightByItem[itemId] = _run(read, itemId, startPosition: startPosition, mediaSourceId: mediaSourceId)
        .whenComplete(() => _inFlightByItem.remove(itemId));
    unawaited(_inFlightByItem[itemId]);
  }

  /// Play path: wait for any in-flight prefetch for this item (and optional MediaSource match).
  static Future<void> waitInFlightForItem(String itemId, {String? mediaSourceId}) async {
    final id = itemId.trim();
    if (id.isEmpty) return;
    final pending = <Future<void>>[];
    final byItem = _inFlightByItem[id];
    if (byItem != null) pending.add(byItem);
    if (pending.isEmpty) return;
    await Future.wait(pending);
  }

  /// Legacy helper — prefers item-scoped wait when [itemId] known.
  static Future<void> waitInFlightForMediaSource(String? mediaSourceId, {String? itemId}) async {
    if (itemId != null && itemId.trim().isNotEmpty) {
      await waitInFlightForItem(itemId, mediaSourceId: mediaSourceId);
      return;
    }
    // Without itemId we cannot safely match coalesced flights; no-op.
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
        await _warmTdlibFromResponse(read, response.body!);
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

  /// Warm TDLib session so play tap hits session cache. Errors are logged; prefetch still succeeds.
  static Future<void> _warmTdlibFromResponse(OxplayerRead read, PlaybackInfoResponse body) async {
    final source = oxplayerResolvePlaybackMediaSource(body);
    final path = source?.path?.trim();
    if (!oxplayerIsTelegramProviderLink(path)) return;
    final sw = Stopwatch()..start();
    try {
      await oxplayerResolveStreamPlaybackUrl(read, path);
      OxplayerStreamLog.event('tdlib_warm', fields: {
        'url': OxplayerStreamLog.describeUrl(path),
        'tdlibWarmMs': sw.elapsedMilliseconds,
        'ok': true,
      });
    } catch (e) {
      OxplayerStreamLog.event('tdlib_warm', fields: {
        'url': OxplayerStreamLog.describeUrl(path),
        'tdlibWarmMs': sw.elapsedMilliseconds,
        'error': e.runtimeType.toString(),
      });
    }
  }
}
