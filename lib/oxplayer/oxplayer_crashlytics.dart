import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:fladder/firebase_options.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_sentry_filters.dart';

/// Firebase Crashlytics alongside Sentry — Google Play / Firebase console crashes.
abstract final class OxplayerCrashlytics {
  static bool _initialized = false;
  static bool _handlersChained = false;

  static bool get isEnabled => _initialized;

  /// Initializes Firebase + Crashlytics when Android/iOS options are configured.
  static Future<void> init() async {
    if (kIsWeb || _initialized) return;

    try {
      final options = await DefaultFirebaseOptions.ensureAndroidResolved();
      await Firebase.initializeApp(options: options);
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
      _initialized = true;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('OXPlayer Crashlytics init skipped: $error\n$stack');
      }
    }
  }

  /// Re-wraps Flutter/platform error handlers after [CrashLogNotifier] and Sentry.
  static void chainErrorHandlers() {
    if (!_initialized || _handlersChained) return;
    _handlersChained = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      unawaited(_recordFlutterError(details));
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      final handled = previousPlatformError?.call(error, stack) ?? false;
      unawaited(_recordPlatformError(error, stack));
      return handled;
    };
  }

  static Future<void> _recordFlutterError(FlutterErrorDetails details) async {
    if (!OxplayerSentryFilters.shouldReportFlutterError(details.exception)) return;
    await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  static Future<void> _recordPlatformError(Object error, StackTrace stack) async {
    if (!OxplayerSentryFilters.shouldReportPlatformError(error)) return;
    await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  }

  /// Records a non-fatal error (same noise filters as Sentry).
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  }) async {
    if (!_initialized) return;
    if (fatal) {
      if (!OxplayerSentryFilters.shouldReportPlatformError(error)) return;
    } else if (!OxplayerSentryFilters.shouldReportPersistedLog(error.toString())) {
      return;
    }
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      fatal: fatal,
      reason: reason,
    );
  }

  static Future<void> log(String message) async {
    if (!_initialized || message.isEmpty) return;
    await FirebaseCrashlytics.instance.log(message);
  }

  static void syncDeviceProfile({required bool leanBack}) {
    if (!_initialized) return;
    unawaited(FirebaseCrashlytics.instance.setCustomKey('leanback', leanBack));
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(FirebaseCrashlytics.instance.setCustomKey('platform', 'android'));
    }
  }

  /// Latest RSS / image-cache samples — visible on next Crashlytics crash/ANR.
  static void syncMemorySnapshot({
    required int? rssMb,
    required int imageCacheMb,
    required int imageCacheCount,
  }) {
    if (!_initialized) return;
    final crashlytics = FirebaseCrashlytics.instance;
    if (rssMb != null) {
      unawaited(crashlytics.setCustomKey('rss_mb', rssMb));
    }
    unawaited(crashlytics.setCustomKey('image_cache_mb', imageCacheMb));
    unawaited(crashlytics.setCustomKey('image_cache_count', imageCacheCount));
  }

  static void setScreen(String screen) {
    if (!_initialized || screen.isEmpty) return;
    unawaited(FirebaseCrashlytics.instance.setCustomKey('screen', screen));
  }

  /// Binds Jellyfin user id only — no PII (mirrors Sentry).
  static void syncUser(AccountModel? account) {
    if (!_initialized) return;
    final crashlytics = FirebaseCrashlytics.instance;
    if (account == null) {
      unawaited(crashlytics.setUserIdentifier(''));
      return;
    }
    final jellyfinUserId = account.id.trim();
    if (jellyfinUserId.isEmpty) {
      unawaited(crashlytics.setUserIdentifier(''));
      return;
    }
    unawaited(crashlytics.setUserIdentifier(jellyfinUserId));
    unawaited(crashlytics.setCustomKey('server_id', account.credentials.serverId));
  }

  /// Forces a native crash so Firebase Crashlytics can be verified from developer mode.
  static void triggerTestCrash() {
    if (!_initialized) return;
    FirebaseCrashlytics.instance.crash();
  }
}
