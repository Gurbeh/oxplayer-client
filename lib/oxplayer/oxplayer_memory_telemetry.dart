import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_crashlytics.dart';

/// RSS above this on phone/tablet triggers a Sentry warning event.
const kOxHighMemoryRssMbPhone = 512;

/// Leanback / Android TV devices often have less headroom.
const kOxHighMemoryRssMbTv = 384;

/// Single navigation RSS jump that triggers a warning (possible leak / retained images).
const kOxHighMemoryNavDeltaMb = 64;

/// Minimum gap between duplicate high-memory warnings for the same screen.
const kOxHighMemoryWarningCooldownMs = 60 * 1000;

/// Point-in-time memory counters for Sentry metrics and navigation breadcrumbs.
final class OxplayerMemorySnapshot {
  const OxplayerMemorySnapshot({
    required this.rssBytes,
    required this.imageCacheBytes,
    required this.imageCacheCount,
    required this.imageCacheMaxBytes,
  });

  final int? rssBytes;
  final int imageCacheBytes;
  final int imageCacheCount;
  final int imageCacheMaxBytes;

  int? get rssMb => rssBytes == null ? null : (rssBytes! / (1024 * 1024)).round();

  Map<String, Object?> toContext() => {
        if (rssBytes != null) 'rss_bytes': rssBytes,
        if (rssMb != null) 'rss_mb': rssMb,
        'image_cache_bytes': imageCacheBytes,
        'image_cache_count': imageCacheCount,
        'image_cache_max_bytes': imageCacheMaxBytes,
      };
}

/// Samples process RSS + Flutter image cache and reports to Sentry on navigation.
abstract final class OxplayerMemoryTelemetry {
  static bool _leanBack = false;
  static OxplayerMemorySnapshot? _lastSnapshot;
  static String? _lastWarningScreen;
  static DateTime? _lastWarningAt;

  /// Called from app root when [ArgumentsModel.leanBackMode] is known.
  static void syncDeviceProfile({required bool leanBack}) {
    _leanBack = leanBack;
    OxplayerCrashlytics.syncDeviceProfile(leanBack: leanBack);
  }

  static OxplayerMemorySnapshot sample() {
    final cache = PaintingBinding.instance.imageCache;
    return OxplayerMemorySnapshot(
      rssBytes: _currentRssBytes(),
      imageCacheBytes: cache.currentSizeBytes,
      imageCacheCount: cache.currentSize,
      imageCacheMaxBytes: cache.maximumSizeBytes,
    );
  }

  static Future<void> onNavigation({
    required String action,
    required String route,
    String? from,
  }) async {
    if (!Sentry.isEnabled || kIsWeb) return;

    final snapshot = sample();
    _emitMetrics(
      snapshot: snapshot,
      action: action,
      route: route,
    );
    OxplayerCrashlytics.setScreen(route);
    final rssMb = snapshot.rssMb;
    if (rssMb != null) {
      unawaited(OxplayerCrashlytics.log('nav:$action $route rss=${rssMb}MB cache=${snapshot.imageCacheBytes}'));
    }
    _addNavigationBreadcrumb(
      snapshot: snapshot,
      action: action,
      route: route,
      from: from,
    );
    await _reportIfHigh(
      snapshot: snapshot,
      action: action,
      route: route,
      from: from,
    );
    _lastSnapshot = snapshot;
  }

  @visibleForTesting
  static int highMemoryThresholdMb({required bool leanBack}) {
    return leanBack ? kOxHighMemoryRssMbTv : kOxHighMemoryRssMbPhone;
  }

  @visibleForTesting
  static bool shouldWarn({
    required OxplayerMemorySnapshot snapshot,
    required OxplayerMemorySnapshot? previous,
    required bool leanBack,
    required String route,
    required String? lastWarningScreen,
    required DateTime? lastWarningAt,
    required DateTime now,
  }) {
    final rss = snapshot.rssBytes;
    if (rss == null) return false;

    final thresholdBytes = highMemoryThresholdMb(leanBack: leanBack) * 1024 * 1024;
    final overAbsolute = rss >= thresholdBytes;

    final prevRss = previous?.rssBytes;
    final deltaBytes = prevRss == null ? 0 : rss - prevRss;
    final overDelta = deltaBytes >= kOxHighMemoryNavDeltaMb * 1024 * 1024;

    if (!overAbsolute && !overDelta) return false;

    if (lastWarningScreen == route &&
        lastWarningAt != null &&
        now.difference(lastWarningAt).inMilliseconds < kOxHighMemoryWarningCooldownMs) {
      return false;
    }

    return true;
  }

  static int? _currentRssBytes() {
    if (kIsWeb) return null;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return null;
    }
  }

  static Map<String, SentryAttribute> _metricAttributes({
    required String action,
    required String route,
  }) {
    return {
      'nav_action': SentryAttribute.string(action),
      'screen': SentryAttribute.string(route),
      'leanback': SentryAttribute.bool(_leanBack),
    };
  }

  static void _emitMetrics({
    required OxplayerMemorySnapshot snapshot,
    required String action,
    required String route,
  }) {
    final attributes = _metricAttributes(action: action, route: route);

    final rss = snapshot.rssBytes;
    if (rss != null) {
      Sentry.metrics.gauge(
        'ox.memory.rss',
        rss,
        unit: SentryMetricUnit.byte,
        attributes: attributes,
      );
    }

    Sentry.metrics.gauge(
      'ox.memory.image_cache_bytes',
      snapshot.imageCacheBytes,
      unit: SentryMetricUnit.byte,
      attributes: attributes,
    );
    Sentry.metrics.gauge(
      'ox.memory.image_cache_count',
      snapshot.imageCacheCount,
      attributes: attributes,
    );
  }

  static void _addNavigationBreadcrumb({
    required OxplayerMemorySnapshot snapshot,
    required String action,
    required String route,
    String? from,
  }) {
    final data = <String, dynamic>{
      'action': action,
      'route': route,
      if (from != null && from.isNotEmpty) 'from': from,
      ...snapshot.toContext(),
    };
    final prev = _lastSnapshot;
    final rss = snapshot.rssBytes;
    final prevRss = prev?.rssBytes;
    if (rss != null && prevRss != null) {
      data['rss_delta_bytes'] = rss - prevRss;
    }

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'memory:$action $route',
        category: 'memory',
        level: SentryLevel.info,
        data: data,
      ),
    );
  }

  static Future<void> _reportIfHigh({
    required OxplayerMemorySnapshot snapshot,
    required String action,
    required String route,
    String? from,
  }) async {
    final now = DateTime.now();
    if (!shouldWarn(
      snapshot: snapshot,
      previous: _lastSnapshot,
      leanBack: _leanBack,
      route: route,
      lastWarningScreen: _lastWarningScreen,
      lastWarningAt: _lastWarningAt,
      now: now,
    )) {
      return;
    }

    _lastWarningScreen = route;
    _lastWarningAt = now;

    final rssMb = snapshot.rssMb ?? 0;
    final prevRss = _lastSnapshot?.rssBytes;
    final deltaMb = prevRss == null || snapshot.rssBytes == null
        ? null
        : ((snapshot.rssBytes! - prevRss) / (1024 * 1024)).round();

    await Sentry.captureMessage(
      'high memory ($route): ${rssMb}MB RSS',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope
          ..setTag('perf', 'high_memory')
          ..setTag('screen', route)
          ..setTag('nav_action', action)
          ..setTag('leanback', _leanBack.toString())
          ..setContexts('memory', {
            'action': action,
            'route': route,
            if (from != null && from.isNotEmpty) 'from': from,
            'threshold_mb': highMemoryThresholdMb(leanBack: _leanBack),
            if (deltaMb != null) 'rss_delta_mb': deltaMb,
            ...snapshot.toContext(),
          });
      },
    );
  }
}
