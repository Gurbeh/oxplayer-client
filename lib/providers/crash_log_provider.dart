import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:fladder/models/error_log_model.dart';
import 'package:fladder/oxplayer/oxplayer_sentry_persisted_logs.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final crashLogProvider = StateNotifierProvider<CrashLogNotifier, List<ErrorLogModel>>((ref) => CrashLogNotifier());

class CrashLogNotifier extends StateNotifier<List<ErrorLogModel>> {
  CrashLogNotifier() : super([]) {
    init();
  }

  final _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  late final Logger logger;
  final maxLength = 50;
  String? logFilePath;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 500);

  void init() async {
    try {
      logger = Logger.root;
      logger.level = Level.ALL;
      logger.onRecord.listen(logPrint);

      FlutterError.onError = (FlutterErrorDetails details) => logFile(details);

      PlatformDispatcher.instance.onError = (error, stack) {
        logFile(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Unhandled',
        ));
        return false;
      };

      if (!kIsWeb) {
        await _initializeLogFile();
        await _loadLogsFromFile();
      }
    } finally {
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    }
  }

  /// Sends persisted severe/shout logs to Sentry once (survives crash/kill).
  Future<void> flushUnreportedToSentry() async {
    if (!Sentry.isEnabled) return;

    if (state.isEmpty) {
      await OxplayerSentryPersistedLogs.flushFromDisk();
      await _loadLogsFromFile();
      return;
    }

    var changed = false;
    final next = <ErrorLogModel>[];

    for (final log in state) {
      if (log.sentryReported) {
        next.add(log);
        continue;
      }
      if (log.type != ErrorType.severe && log.type != ErrorType.shout) {
        next.add(log);
        continue;
      }

      await OxplayerSentryPersistedLogs.capture(log);
      next.add(log.copyWith(sentryReported: true));
      changed = true;
    }

    if (changed) {
      state = next;
      _debounceTimer?.cancel();
      await _saveLogsToFile();
    }
  }

  Future<void> _initializeLogFile() async {
    final directory = await getApplicationCacheDirectory();
    logFilePath = '${directory.path}/crash_logs.json';
  }

  Future<void> _loadLogsFromFile() async {
    if (logFilePath == null) return;

    try {
      final file = File(logFilePath!);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> jsonData = jsonDecode(content);
      state = jsonData.map((json) => ErrorLogModel.fromJson(json)).toList();
    } catch (e) {
      print('Failed to load crash logs: $e');
    }
  }

  Future<void> _saveLogsToFile() async {
    if (logFilePath == null) return;

    try {
      final file = File(logFilePath!);
      final jsonData = state.map((log) => log.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      print('Failed to save crash logs: $e');
    }
  }

  Future<void> clearLogs() async {
    state = [];
    if (!kIsWeb) {
      _debounceTimer?.cancel();
      await _saveLogsToFile();
    }
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _saveLogsToFile();
    });
  }

  void logPrint(LogRecord rec) {
    if (kDebugMode) {
      print('${rec.level.name}: ${rec.time}: ${rec.message}');
    }
    if (rec.level > Level.INFO) {
      state = [ErrorLogModel.fromLogRecord(rec), ...state];
      if (state.length >= maxLength) {
        state = state.sublist(0, maxLength);
      }
      if (!kIsWeb) {
        _scheduleSave();
      }
    }
  }

  void logFile(FlutterErrorDetails details) {
    logger.severe('Flutter error: ${details.exception}', details.exception, details.stack);
    if (details.stack != null && kDebugMode) {
      print('${details.stack}');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
