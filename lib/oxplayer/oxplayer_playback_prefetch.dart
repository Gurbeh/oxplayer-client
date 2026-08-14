import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/oxplayer/ox_series_next_up.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_delivery_reader_sync.dart';
import 'package:fladder/oxplayer/oxplayer_playback_info_polling.dart';
import 'package:fladder/oxplayer/oxplayer_playback_link_cache.dart';
import 'package:fladder/oxplayer/oxplayer_playback_media_source.dart';
import 'package:fladder/oxplayer/oxplayer_provider_bots_bootstrap.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Warms PlaybackInfo (public-provider copy) and caches the playable t.me link in-memory.
abstract final class OxplayerPlaybackPrefetch {
  /// In-flight keyed by itemId — any mediaSourceId for same item shares one flight.
  static final Map<String, Future<void>> _inFlightByItem = {};
  /// Home slider: PlaybackInfo itself triggers copyMessage. One attempt per item per process
  /// so a never-reported miss (oxm_dev_510) cannot recopy on every fetchViews.
  static final Set<String> _homeOnceItems = {};

  /// Fire-and-forget when detail screen knows the likely play target.
  static void scheduleForSeries(OxplayerRead read, SeriesModel? series, {bool once = false}) {
    if (!OxplayerConfig.isEnabled || series == null) return;
    final episode = oxSeriesPlayableNextUp(series);
    if (episode == null) return;
    scheduleForItem(
      read,
      episode.id,
      startPosition: episode.userData.playBackPosition,
      mediaSourceId: episode.streamModel?.currentVersionStream?.id,
      once: once,
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
    bool once = false,
  }) {
    if (!OxplayerConfig.isEnabled || itemId.isEmpty || kIsWeb) return;
    if (once && !_homeOnceItems.add(itemId)) return;
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
    await oxplayerEnsureTdlibMatchesOxUser(read(userProvider)?.credentials.token);
    if (oxplayerTdlibPlayInProgress()) {
      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'skipped': 'play_in_progress',
      });
      return;
    }
    // startBot MUST finish before PlaybackInfo: a miss copyMessage into an unstarted DM is
    // Telegram 400 chat not found, and the client then spins 20s on oxplayer-tg://0/0.
    final botsReady = await OxplayerProviderBotsBootstrap.ensureReady();
    if (!botsReady) {
      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'skipped': 'provider_bots_not_ready',
      });
      return;
    }

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

      final playbackInfoMs = sw.elapsedMilliseconds;
      if (response.isSuccessful && response.body != null) {
        await _warmTdlibFromResponse(read, response.body!);
        OxplayerPlaybackLinkCache.putFromResponse(response.body);
      }

      OxplayerStreamLog.event('playback_prefetch', fields: {
        'itemId': itemId,
        'mediaSourceId': mediaSourceId,
        'cached': response.body != null,
        'playbackInfoMs': playbackInfoMs,
        'totalMs': sw.elapsedMilliseconds,
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

  /// Resolves the delivery and reports where it landed, so the eventual play is answered from the
  /// backend's delivery table with no Telegram copy at all.
  ///
  /// Deliberately does NOT open a download session. Scrolling the dashboard warms several titles at
  /// once, and starting a progressive download per warmed item would spend the user's data on bytes
  /// for videos nobody pressed play on. Resolving is the whole point: it makes the backend remember
  /// the message id. Errors are logged; the prefetch still counts as succeeded.
  static Future<void> _warmTdlibFromResponse(OxplayerRead read, PlaybackInfoResponse body) async {
    final source = oxplayerResolvePlaybackMediaSource(body);
    final path = source?.path?.trim();
    if (path == null || !oxplayerIsTelegramProviderLink(path)) return;
    final parsed = oxplayerParseTelegramDeliveryPath(path);
    if (parsed == null) return;
    if (oxplayerTdlibPlayInProgress() || oxplayerTdlibPlayIsResolving(parsed.locator)) {
      OxplayerStreamLog.event('tdlib_warm', fields: {
        'url': OxplayerStreamLog.describeUrl(path),
        'skipped': 'play_resolving',
      });
      return;
    }
    final controller = OxplayerTdlibBridgeController.instance();
    final sw = Stopwatch()..start();
    try {
      // Arm before resolving: on a miss the backend already sent the copy while PlaybackInfo was
      // in flight, so the push can land before anything is waiting for it.
      await controller.armDeliveryWaiter(parsed.locator);
      // Prefer the live-push ref over a competing 0/0 warmDelivery — that shared waiter
      // made play timeout while prefetch held the channel.
      final landed = await waitForTdlibDeliveryRef(
        controller,
        parsed.locator,
        timeout: const Duration(seconds: 8),
      );
      if (landed == null || landed.messageId <= 0) {
        if (oxplayerTdlibPlayInProgress()) {
          OxplayerStreamLog.event('tdlib_warm', fields: {
            'url': OxplayerStreamLog.describeUrl(path),
            'skipped': 'play_in_progress',
          });
          return;
        }
        await controller.warmDelivery(parsed.toSource());
      }
      await oxplayerReportTelegramDelivery(controller, locator: parsed.locator);
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
