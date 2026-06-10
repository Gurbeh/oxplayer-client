import 'package:sentry_flutter/sentry_flutter.dart';

/// Reports to Sentry when cold-start splash exceeds [kOxSlowSplashThresholdMs].
const kOxSlowSplashThresholdMs = 2000;

/// Tracks splash phases and reports slow startups with a breakdown of where time went.
final class OxplayerSplashTiming {
  final Stopwatch _total = Stopwatch();
  Stopwatch? _sessionRestore;

  int _firstFrameMs = 0;
  int _afterInitialDelayMs = 0;
  int _sessionRestoreMs = 0;

  String? _authMethod;
  bool _hadAccount = false;
  bool _newWindow = false;
  bool? _sessionOk;
  bool _reported = false;

  void markStarted() => _total.start();

  void markFirstFrame() {
    _firstFrameMs = _total.elapsedMilliseconds;
  }

  void markAfterInitialDelay() {
    _afterInitialDelayMs = _total.elapsedMilliseconds;
  }

  void markAccountContext({
    required bool hadAccount,
    required bool newWindow,
    String? authMethod,
  }) {
    _hadAccount = hadAccount;
    _newWindow = newWindow;
    _authMethod = authMethod;
  }

  void markSessionRestoreStarted() {
    _sessionRestore = Stopwatch()..start();
  }

  void markSessionRestoreEnded(bool ok) {
    _sessionOk = ok;
    final sw = _sessionRestore;
    if (sw != null && sw.isRunning) {
      sw.stop();
      _sessionRestoreMs = sw.elapsedMilliseconds;
    }
  }

  /// Call once before leaving the splash route.
  Future<void> finishAndReport({
    required String destination,
    required bool loggedIn,
  }) async {
    if (_reported || !_total.isRunning) return;
    _reported = true;
    _total.stop();

    final totalMs = _total.elapsedMilliseconds;
    if (totalMs < kOxSlowSplashThresholdMs || !Sentry.isEnabled) return;

    final preSessionMs = (_afterInitialDelayMs - _firstFrameMs).clamp(0, totalMs);
    final reason = _slowReason(
      totalMs: totalMs,
      firstFrameMs: _firstFrameMs,
      preSessionMs: preSessionMs,
      sessionRestoreMs: _sessionRestoreMs,
      authMethod: _authMethod,
      hadAccount: _hadAccount,
      newWindow: _newWindow,
    );

    await Sentry.captureMessage(
      'slow splash screen (${totalMs}ms): $reason',
      level: SentryLevel.warning,
      withScope: (scope) {
        scope
          ..setTag('perf', 'slow_splash')
          ..setTag('splash.destination', destination)
          ..setTag('splash.logged_in', loggedIn.toString())
          ..setTag('splash.reason', reason)
          ..setContexts('splash', {
            'total_ms': totalMs,
            'first_frame_ms': _firstFrameMs,
            'after_initial_delay_ms': _afterInitialDelayMs,
            'pre_session_ms': preSessionMs,
            'session_restore_ms': _sessionRestoreMs,
            'had_account': _hadAccount,
            'new_window': _newWindow,
            'auth_method': _authMethod,
            'session_ok': _sessionOk,
            'destination': destination,
            'logged_in': loggedIn,
            'reason': reason,
          });
      },
    );
  }

  static String _slowReason({
    required int totalMs,
    required int firstFrameMs,
    required int preSessionMs,
    required int sessionRestoreMs,
    required bool hadAccount,
    required bool newWindow,
    String? authMethod,
  }) {
    if (!hadAccount || newWindow) {
      return 'no_session_restore';
    }
    if (authMethod != null && authMethod != 'autoLogin') {
      return 'auth_method_$authMethod';
    }

    final candidates = <(String, int)>[
      ('session_restore', sessionRestoreMs),
      ('pre_session', preSessionMs),
      ('first_frame', firstFrameMs),
    ];
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    final dominant = candidates.first;
    if (dominant.$2 <= 0) {
      return 'unknown_overhead';
    }

    final overheadMs = totalMs - firstFrameMs - preSessionMs - sessionRestoreMs - 500;
    if (overheadMs > 500 && dominant.$1 != 'session_restore') {
      return '${dominant.$1}+overhead';
    }
    return dominant.$1;
  }
}
