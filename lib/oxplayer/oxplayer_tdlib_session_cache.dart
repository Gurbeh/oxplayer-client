import 'dart:async';

import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// In-memory cache of resolved TDLib playback URLs keyed by Telegram public link + bridge mode.
///
/// Process-lifetime only. Short TTL so a purged public-pool message does not stick forever.
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

  static void put(String telegramUrl, String resolvedUrl, {required bool preferHttpBridge}) {
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

  static String? _canonicalTelegramUrl(String? url) {
    if (!oxplayerIsTelegramProviderLink(url)) return null;
    final uri = Uri.parse(url!.trim());
    return 'https://t.me/${uri.pathSegments[0]}/${uri.pathSegments[1]}';
  }
}

class _Entry {
  _Entry({required this.resolvedUrl, required this.storedAt});

  final String resolvedUrl;
  final DateTime storedAt;

  bool get isFresh => DateTime.now().difference(storedAt) < OxplayerTdlibSessionCache.ttl;
}
