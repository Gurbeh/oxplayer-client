import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_diag_hooks.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
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

    onPhase?.call('collecting_context');
    final report = <String, Object?>{
      'kind': 'oxplayer_playback_diag',
      'capturedAt': started.toIso8601String(),
      'app': await _appContext(),
      'user': _userContext(),
      'route': _routeContext(),
      'playback': _playbackContext(),
    };

    if (_cancelled) return _encode(report);

    onPhase?.call('probing_api');
    report['probes'] = await _runProbes();

    if (_cancelled) {
      if (kIsWeb) OxplayerPlaybackDiagHooks.uninstall();
      return _encode(report);
    }

    if (kIsWeb) {
      onPhase?.call('watching_playback');
      OxplayerPlaybackDiagHooks.install();
      await _watchWeb(const Duration(seconds: 30));
      if (!_cancelled) {
        report['webHooks'] = OxplayerPlaybackDiagHooks.snapshot();
      }
      OxplayerPlaybackDiagHooks.uninstall();
    }

    report['checks'] = _deriveChecks(report);
    return _encode(report);
  }

  String _encode(Map<String, Object?> report) {
    return const JsonEncoder.withIndent('  ').convert(report);
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

  Map<String, Object?> _routeContext() {
    return {
      'activeEdge': OxplayerRoute.active.name,
      'apiBaseUrl': OxplayerRoute.apiBaseUrl,
      'connectBaseUrl': OxplayerRoute.connectBaseUrl,
      'streamVanity': OxplayerRoute.streamBaseUrl,
      'iranApiEnv': OxplayerRouteEnv.iranApiBaseUrl,
      'iranStreamEnv': OxplayerRouteEnv.iranStreamBaseUrl,
      'usesIranStreamVanity': OxplayerRouteEnv.usesIranStreamVanity,
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
      'isOxStreamUrl': oxplayerIsOxStreamUrl(url),
      'isIranVanity': url != null && url.contains('.ir.cdn.ir'),
      'isStreamOxplayerIr': url != null && url.contains('stream.oxplayer.ir'),
      'isRemuxTs': url != null && url.contains('stream.ts'),
    };
  }

  Future<Map<String, Object?>> _runProbes() async {
    final out = <String, Object?>{};
    final base = _ref.read(serverUrlProvider)?.trim() ?? '';
    final token = _ref.read(userProvider)?.credentials.token.trim() ?? '';

    if (base.isEmpty) {
      out['error'] = 'no_server_url';
      return out;
    }

    out['health'] = await _probeGet('$base/health', token: null);
    if (token.isNotEmpty) {
      out['streamNodes'] = await _probeStreamNodes(base, token);
    } else {
      out['streamNodes'] = {'skipped': true, 'reason': 'no_token'};
    }

    final playbackUrl = _ref.read(playBackModel)?.media?.url;
    if (playbackUrl != null && playbackUrl.isNotEmpty) {
      out['playbackHead'] = await _probeHead(playbackUrl);
    }

    return out;
  }

  Future<Map<String, Object?>> _probeStreamNodes(String base, String token) async {
    final sw = Stopwatch()..start();
    try {
      final api = OxplayerStreamNodesApi();
      final nodes = await api.fetchHealthyNodes(
        baseUrl: base,
        accessToken: token,
        forceRefresh: true,
      );
      sw.stop();
      return {
        'ok': nodes.isNotEmpty,
        'count': nodes.length,
        'hosts': nodes.map((n) => Uri.tryParse(n.url)?.host).whereType<String>().toList(),
        'elapsedMs': sw.elapsedMilliseconds,
      };
    } catch (e) {
      sw.stop();
      return {
        'ok': false,
        'error': e.runtimeType.toString(),
        'elapsedMs': sw.elapsedMilliseconds,
      };
    }
  }

  Future<Map<String, Object?>> _probeGet(String url, {String? token}) async {
    final sw = Stopwatch()..start();
    try {
      final headers = <String, String>{
        if (OxplayerRoute.active == OxplayerEdge.iran) 'X-Ox-Edge': 'iran',
        ...OxplayerRoute.connectHeaders,
      };
      final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 8));
      sw.stop();
      return {
        'url': url,
        'status': res.statusCode,
        'elapsedMs': sw.elapsedMilliseconds,
        'xOxRouteRequired': res.headers['x-ox-route-required'],
        'xOxClientCountry': res.headers['x-ox-client-country'] ?? res.headers['cf-ipcountry'],
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

  Future<Map<String, Object?>> _probeHead(String url) async {
    final sw = Stopwatch()..start();
    try {
      final req = http.Request('GET', Uri.parse(url))..headers['Range'] = 'bytes=0-0';
      final client = http.Client();
      try {
        final res = await client.send(req).timeout(const Duration(seconds: 8));
        await res.stream.drain();
        sw.stop();
        return {
          'url': OxplayerStreamLog.describeUrl(url),
          'status': res.statusCode,
          'acao': res.headers['access-control-allow-origin'],
          'elapsedMs': sw.elapsedMilliseconds,
        };
      } finally {
        client.close();
      }
    } catch (e) {
      sw.stop();
      return {
        'url': OxplayerStreamLog.describeUrl(url),
        'ok': false,
        'error': e.runtimeType.toString(),
        'elapsedMs': sw.elapsedMilliseconds,
      };
    }
  }

  Map<String, Object?> _deriveChecks(Map<String, Object?> report) {
    final playback = report['playback'];
    final webHooks = report['webHooks'];
    final probes = report['probes'];

    final checks = <String, Object?>{
      'apiHealthOk': _probeOk(probes, 'health'),
      'streamNodesOk': _nodesOk(probes),
    };

    if (playback is Map<String, Object?>) {
      checks['playbackUsesStreamOxplayerIr'] = playback['isStreamOxplayerIr'] == true;
      checks['playbackUsesIranVanity'] = playback['isIranVanity'] == true;
      checks['playbackUsesRemuxTs'] = playback['isRemuxTs'] == true;
    }

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

  bool _nodesOk(Object? probes) {
    if (probes is! Map) return false;
    final nodes = probes['streamNodes'];
    if (nodes is! Map) return false;
    return nodes['ok'] == true;
  }
}
