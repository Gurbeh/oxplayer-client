import 'dart:async';

import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// In-memory cache of resolved TDLib playback URLs keyed by Telegram public link + bridge mode.
///
/// Process-lifetime only. Short TTL so a purged public-pool message does not stick forever.
///
/// Session-bound urls are NEVER stored — see [put]. In practice that rules out every resolved
/// Telegram transport, so this degrades to a singleflight (see [resolveOrStart]) plus a cache for
/// any future non-session-bound resolution. That is deliberate and costs little: the expensive half
/// of a resolve (finding which DM message holds the file, and copying it there if it is missing) is
/// already remembered natively in go/oxtelegram's deliveryRefs for 10 minutes, so a second play of
/// the same title re-runs startPlaybackSession against a warm client and a known message id rather
/// than triggering a fresh server-side copy.
abstract final class OxplayerTdlibSessionCache {
  static const Duration ttl = Duration(minutes: 15);

  static final Map<String, _Entry> _entries = {};
  static final Map<String, Future<String>> _inFlight = {};

  static String cacheKey(String telegramUrl, {required bool preferHttpBridge}) {
    final canonical = _canonicalTelegramUrl(telegramUrl) ?? telegramUrl.trim();
    return '$canonical|hb=${preferHttpBridge ? 1 : 0}';
  }

  static String? get(String telegramUrl, {required bool preferHttpBridge}) {
    final key = cacheKey(telegramUrl, preferHttpBridge: preferHttpBridge);
    final entry = _entries[key];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _entries.remove(key);
      return null;
    }
    return entry.resolvedUrl;
  }

  /// Stores [resolvedUrl] unless it dies with the playback session that minted it.
  ///
  /// The synthetic id in `tdlib-file://{id}` / `http://127.0.0.1:{port}/{id}` / `gotdstream://{id}`
  /// is a per-session counter, not a locator: replaying a stored one after its fileFetcher was torn
  /// down is exactly the dead-playback bug this guard exists to prevent. Silently skipping (rather
  /// than throwing) keeps [resolveOrStart] a plain pass-through for those urls.
  static void put(String telegramUrl, String resolvedUrl, {required bool preferHttpBridge}) {
    if (oxplayerIsSessionBoundPlaybackUrl(resolvedUrl)) return;
    final key = cacheKey(telegramUrl, preferHttpBridge: preferHttpBridge);
    _entries[key] = _Entry(resolvedUrl: resolvedUrl, storedAt: DateTime.now());
  }

  /// Resolve with cache + singleflight so prefetch and play share one TDLib session start.
  static Future<String> resolveOrStart(
    String telegramUrl, {
    required bool preferHttpBridge,
    required Future<String> Function() start,
  }) async {
    final cached = get(telegramUrl, preferHttpBridge: preferHttpBridge);
    if (cached != null) return cached;

    final key = cacheKey(telegramUrl, preferHttpBridge: preferHttpBridge);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = () async {
      final resolved = await start();
      put(telegramUrl, resolved, preferHttpBridge: preferHttpBridge);
      return resolved;
    }();
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  static void invalidateTelegramUrl(String? telegramUrl) {
    final canonical = _canonicalTelegramUrl(telegramUrl);
    if (canonical == null) return;
    _entries.removeWhere((k, _) => k.startsWith('$canonical|'));
    _inFlight.removeWhere((k, _) => k.startsWith('$canonical|'));
  }

  static void clearAll() {
    _entries.clear();
    _inFlight.clear();
  }

  /// The locator alone, not the Path.
  ///
  /// A cold play carries `oxplayer-tg://0/0` — the backend has not committed to a sender yet — so
  /// keying on bot+message id would canonicalise EVERY not-yet-remembered file to the same string
  /// and hand one title's resolved url to another. The locator is unique per stored file, and it
  /// stays the same string once the ids get filled in, so a warm entry survives the miss→hit
  /// transition instead of being orphaned by it.
  static String? _canonicalTelegramUrl(String? url) {
    final parsed = url == null ? null : oxplayerParseTelegramDeliveryPath(url.trim());
    if (parsed == null) return null;
    return 'oxdelivery:${parsed.locator}';
  }
}

class _Entry {
  _Entry({required this.resolvedUrl, required this.storedAt});

  final String resolvedUrl;
  final DateTime storedAt;

  bool get isFresh => DateTime.now().difference(storedAt) < OxplayerTdlibSessionCache.ttl;
}
