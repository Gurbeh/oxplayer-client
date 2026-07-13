import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_memory_telemetry.dart';

/// Reports screens whose first frame after navigation exceeds this threshold.
const kOxSlowScreenFirstFrameMs = 2500;

/// Reports async screen loads (e.g. detail fetch) exceeding this threshold.
const kOxSlowScreenLoadMs = 3000;

/// Sentry performance hints for slow navigation and data loads.
abstract final class OxplayerScreenTelemetry {
  static Future<T> trackLoad<T>({
    required String screen,
    String phase = 'load',
    required Future<T> Function() load,
  }) async {
    final sw = Stopwatch()..start();
    try {
      return await load();
    } finally {
      sw.stop();
      await reportIfSlow(
        screen: screen,
        phase: phase,
        ms: sw.elapsedMilliseconds,
        thresholdMs: kOxSlowScreenLoadMs,
      );
    }
  }

  static Future<void> reportIfSlow({
    required String screen,
    required String phase,
    required int ms,
    required int thresholdMs,
  }) async {
    if (ms < thresholdMs || !Sentry.isEnabled) return;

    await Sentry.captureMessage(
      'slow screen ($screen): ${ms}ms ($phase)',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope
          ..setTag('perf', 'slow_screen')
          ..setTag('screen', screen)
          ..setTag('screen.phase', phase)
          ..setContexts('screen_perf', {
            'screen': screen,
            'phase': phase,
            'duration_ms': ms,
            'threshold_ms': thresholdMs,
          });
      },
    );
  }
}

/// Measures time from route push to first frame (navigation + initial paint).
final class OxplayerRouteTelemetryObserver extends NavigatorObserver {
  final Map<Route<dynamic>, Stopwatch> _pending = {};
  String? _lastRoute;
  DateTime? _lastRouteAt;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
    final from = previousRoute != null ? _routeName(previousRoute) : _lastRoute;
    _recordNavigationBreadcrumb(
      action: 'push',
      route: name,
      from: from,
    );
    _lastRoute = name;
    _lastRouteAt = DateTime.now();

    final sw = Stopwatch()..start();
    _pending[route] = sw;

    SchedulerBinding.instance.scheduleFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final active = _pending.remove(route);
        if (active == null || !active.isRunning) return;
        active.stop();
        OxplayerScreenTelemetry.reportIfSlow(
          screen: name,
          phase: 'first_frame',
          ms: active.elapsedMilliseconds,
          thresholdMs: kOxSlowScreenFirstFrameMs,
        );
        OxplayerMemoryTelemetry.onNavigation(
          action: 'push',
          route: name,
          from: from,
        );
      });
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pending.remove(route)?.stop();
    final name = _routeName(route);
    final to = previousRoute != null ? _routeName(previousRoute) : null;
    _recordNavigationBreadcrumb(
      action: 'pop',
      route: name,
      from: to,
    );
    OxplayerMemoryTelemetry.onNavigation(
      action: 'pop',
      route: to ?? name,
      from: name,
    );
    if (previousRoute != null) {
      _lastRoute = _routeName(previousRoute);
      _lastRouteAt = DateTime.now();
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pending.remove(route)?.stop();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _pending.remove(oldRoute)?.stop();
    }
    if (newRoute != null) {
      didPush(newRoute, oldRoute);
    }
  }

  static String _routeName(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return route.runtimeType.toString();
  }

  void _recordNavigationBreadcrumb({
    required String action,
    required String route,
    String? from,
  }) {
    if (!Sentry.isEnabled) return;

    final data = <String, dynamic>{
      'action': action,
      'route': route,
      if (from != null && from.isNotEmpty) 'from': from,
    };
    final lastAt = _lastRouteAt;
    if (lastAt != null) {
      data['ms_since_last'] = DateTime.now().difference(lastAt).inMilliseconds;
    }

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: 'nav:$action $route',
        category: 'navigation',
        level: SentryLevel.info,
        data: data,
      ),
    );
  }
}
