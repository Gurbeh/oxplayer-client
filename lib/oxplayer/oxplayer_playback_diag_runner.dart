import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_diag_hooks.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/application_info.dart';

/// Collects playback diagnostics for support (API probes + optional web video hooks).
class OxplayerPlaybackDiagRunner {
  OxplayerPlaybackDiagRunner(WidgetRef ref) : _ref = ref;

  final WidgetRef _ref;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Future<String> run({void Function(String phase)? onPhase}) async {
    _cancelled = false;
    final started = DateTime.now().toUtc();
    final report = <String, Object?>{
      'kind': 'oxplayer_playback_diag',
      'capturedAt': started.toIso8601String(),
    };
    final phaseErrors = <String, String>{};

    onPhase?.call('collecting_context');
    try {
      report['app'] = await _appContext();
      report['user'] = _userContext();
      report['playback'] = _playbackContext();
    } catch (e) {
      phaseErrors['collecting_context'] = e.toString();
    }

    if (_cancelled) return _encode(report, phaseErrors);

    onPhase?.call('probing_api');
    try {
      report['probes'] = await _runProbes();
    } catch (e) {
      phaseErrors['probing_api'] = e.toString();
      report['probes'] = {'ok': false, 'error': e.toString()};
    }

    if (_cancelled) {
      if (kIsWeb) OxplayerPlaybackDiagHooks.uninstall();
      return _encode(report, phaseErrors);
    }

    if (kIsWeb) {
      onPhase?.call('watching_playback');
      try {
        OxplayerPlaybackDiagHooks.install();
        await _watchWeb(const Duration(seconds: 5));
        if (!_cancelled) {
          report['webHooks'] = OxplayerPlaybackDiagHooks.snapshot();
        }
      } catch (e) {
        phaseErrors['watching_playback'] = e.toString();
        report['webHooks'] = {'ok': false, 'error': e.toString()};
      } finally {
        OxplayerPlaybackDiagHooks.uninstall();
      }
    }

    try {
      report['checks'] = _deriveChecks(report);
    } catch (e) {
      phaseErrors['derive_checks'] = e.toString();
    }

    return _encode(report, phaseErrors);
  }

  String _encode(Map<String, Object?> report, [Map<String, String>? phaseErrors]) {
    if (phaseErrors != null && phaseErrors.isNotEmpty) {
      report['phaseErrors'] = phaseErrors;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(report);
    } catch (e) {
      return const JsonEncoder.withIndent('  ').convert({
        'kind': report['kind'],
        'capturedAt': report['capturedAt'],
        'encodeError': e.toString(),
        'phaseErrors': phaseErrors,
      });
    }
  }

  Future<void> _watchWeb(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end) && !_cancelled) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<Map<String, Object?>> _appContext() async {
    final info = _ref.read(applicationInfoProvider);
    List<ConnectivityResult> connectivity = const [];
    try {
      connectivity = await Connectivity().checkConnectivity();
    } catch (_) {}

    return {
      'name': info.name,
      'version': info.version,
      'buildNumber': info.buildNumber,
      'platform': info.platform.name,
      'versionAndPlatform': info.versionAndPlatform,
      'isWeb': kIsWeb,
      'oxplayerEnabled': OxplayerEnv.isEnabled,
      'connectivity': connectivity.map((c) => c.name).toList(),
    };
  }

  Map<String, Object?> _userContext() {
    final user = _ref.read(userProvider);
    final token = user?.credentials.token.trim() ?? '';
    final server = _ref.read(serverUrlProvider)?.trim();
    return {
      'userId': user?.id,
      'userName': user?.name,
      'serverUrl': server,
      'hasAuthToken': token.isNotEmpty,
      'authTokenLength': token.isEmpty ? 0 : token.length,
    };
  }

  Map<String, Object?> _playbackContext() {
    final model = _ref.read(playBackModel);
    final media = model?.media;
    final url = media?.url;
    return {
      'hasActivePlayback': model != null,
      'itemId': model?.item.id,
      'itemName': model?.item.name,
      'streamUrl': OxplayerStreamLog.describeUrl(url),
      'streamHost': OxplayerStreamLog.describeHost(url),
    };
  }

  Future<Map<String, Object?>> _runProbes() async {
    final out = <String, Object?>{};
    final base = _ref.read(serverUrlProvider)?.trim() ?? '';

    if (base.isEmpty) {
      out['error'] = 'no_server_url';
      return out;
    }

    out['health'] = await _probeGet('$base/health');

    return out;
  }

  Future<Map<String, Object?>> _probeGet(String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      sw.stop();
      return {
        'url': url,
        'status': res.statusCode,
        'elapsedMs': sw.elapsedMilliseconds,
      };
    } catch (e) {
      sw.stop();
      return {
        'url': url,
        'ok': false,
        'error': e.runtimeType.toString(),
        'elapsedMs': sw.elapsedMilliseconds,
      };
    }
  }

  Map<String, Object?> _deriveChecks(Map<String, Object?> report) {
    final webHooks = report['webHooks'];
    final probes = report['probes'];

    final checks = <String, Object?>{
      'apiHealthOk': _probeOk(probes, 'health'),
    };

    if (webHooks is Map<String, Object?>) {
      final webChecks = webHooks['checks'];
      if (webChecks is Map) {
        checks.addAll(webChecks.cast<String, Object?>());
      }
    }

    return checks;
  }

  bool _probeOk(Object? probes, String key) {
    if (probes is! Map) return false;
    final probe = probes[key];
    if (probe is! Map) return false;
    final status = probe['status'];
    return status is int && status >= 200 && status < 500;
  }
}
