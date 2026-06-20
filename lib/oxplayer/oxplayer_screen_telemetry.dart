import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = _routeName(route);
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
      });
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _pending.remove(route)?.stop();
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
}
