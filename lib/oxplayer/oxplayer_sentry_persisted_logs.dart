import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:fladder/models/error_log_model.dart';

/// Uploads errors persisted in [crash_logs.json] that were not sent before a crash/kill.
abstract final class OxplayerSentryPersistedLogs {
  static const _logFileName = 'crash_logs.json';

  static Future<void> capture(ErrorLogModel log) => _capture(log);

  static Future<void> flushFromDisk() async {
    if (!Sentry.isEnabled || kIsWeb) return;

    final file = await _logFile();
    if (file == null || !await file.exists()) return;

    try {
      final content = await file.readAsString();
      if (content.isEmpty) return;

      final raw = jsonDecode(content);
      if (raw is! List<dynamic>) return;

      var changed = false;
      final updated = <Map<String, dynamic>>[];

      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final log = ErrorLogModel.fromJson(entry);
        final alreadyReported = entry['sentryReported'] == true;

        if (!alreadyReported && _shouldReportToSentry(log)) {
          await _capture(log);
          entry['sentryReported'] = true;
          changed = true;
        }

        updated.add(entry);
      }

      if (changed) {
        await file.writeAsString(jsonEncode(updated));
      }
    } catch (_) {
      // Best-effort; local logs remain for the user.
    }
  }

  static bool _shouldReportToSentry(ErrorLogModel log) {
    return log.type == ErrorType.severe || log.type == ErrorType.shout;
  }

  static Future<void> _capture(ErrorLogModel log) async {
    final level = switch (log.type) {
      ErrorType.severe => SentryLevel.error,
      ErrorType.shout => SentryLevel.fatal,
      ErrorType.warning => SentryLevel.warning,
    };

    await Sentry.captureException(
      Exception(log.message),
      stackTrace: log.stackTrace,
      withScope: (scope) {
        scope
          ..level = level
          ..setTag('source', 'persisted_error_log')
          ..setTag('error_log.type', log.type.name)
          ..setContexts('persisted_error_log', {
            'logged_at': log.time.toIso8601String(),
            'message': log.message,
          });
      },
    );
  }

  static Future<File?> _logFile() async {
    try {
      final dir = await getApplicationCacheDirectory();
      return File('${dir.path}/$_logFileName');
    } catch (_) {
      return null;
    }
  }
}
