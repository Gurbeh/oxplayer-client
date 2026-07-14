import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_iran_stream_edge.dart';
import 'package:fladder/oxplayer/oxplayer_playback_diag_hooks.dart';
import 'package:fladder/oxplayer/oxplayer_playback_media_source.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/oxplayer/oxplayer_stream_url_resolver.dart';
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

    onPhase?.call('probing_playback');
    report['playbackProbe'] = await _runPlaybackProbe();

    if (_cancelled) {
      if (kIsWeb) OxplayerPlaybackDiagHooks.uninstall();
      return _encode(report);
    }

    if (kIsWeb) {
      onPhase?.call('watching_playback');
      OxplayerPlaybackDiagHooks.install();
      await _watchWeb(const Duration(seconds: 5));
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

    out['cdnRange'] = await _probeCdnRangeEndpoints();

    final playbackUrl = _ref.read(playBackModel)?.media?.url;
    if (playbackUrl != null && playbackUrl.isNotEmpty) {
      out['playbackHead'] = await _probeHead(playbackUrl);
    }

    return out;
  }

  Future<Map<String, Object?>> _probeCdnRangeEndpoints() async {
    final vanity = (OxplayerRoute.streamBaseUrl ?? '').trim().replaceAll(RegExp(r'/$'), '');
    final targets = <String>{
      'https://${OxplayerIranStreamEdge.iranStreamOriginHost}/cdn-probe/range',
      if (vanity.isNotEmpty) '$vanity/cdn-probe/range',
    };
    final results = <String, Object?>{};
    for (final url in targets) {
      results[Uri.parse(url).host] = kIsWeb
          ? await OxplayerPlaybackDiagHooks.probeCdnRange(url)
          : await _probeHead(url);
    }
    return results;
  }

  Future<Map<String, Object?>> _runPlaybackProbe() async {
    final out = <String, Object?>{};
    final user = _ref.read(userProvider);
    if (user == null) {
      return {'skipped': true, 'reason': 'no_user'};
    }

    var itemId = _ref.read(playBackModel)?.item.id;
    var itemName = _ref.read(playBackModel)?.item.name;
    var apiMinted = _ref.read(playBackModel)?.media?.url;
    apiMinted = apiMinted?.trim();

    if (apiMinted == null || apiMinted.isEmpty) {
      out['source'] = 'resume';
      final resume = await _fetchResumePlaybackUrl(user.id);
      out.addAll(resume);
      if (resume['apiMinted'] is String) {
        apiMinted = resume['apiMinted'] as String;
      }
      itemId ??= resume['itemId'] as String?;
      itemName ??= resume['itemName'] as String?;
    } else {
      out['source'] = 'active_playback';
    }

    out['itemId'] = itemId;
    out['itemName'] = itemName;

    if (apiMinted == null || apiMinted.isEmpty) {
      out['skipped'] = true;
      out['reason'] = out['reason'] ?? 'no_playable_url';
      return out;
    }

    out['apiMinted'] = OxplayerStreamLog.describeUrl(apiMinted);
    out['apiMintedHost'] = OxplayerStreamLog.describeHost(apiMinted);

    if (!oxplayerIsOxStreamUrl(apiMinted)) {
      out['skipped'] = true;
      out['reason'] = 'not_ox_stream';
      return out;
    }

    final resolved = await oxplayerResolveStreamPlaybackUrl(
      _ref.read,
      apiMinted,
      forceRefreshNodes: true,
    );
    final finalUrl = resolved ?? apiMinted;
    out['resolved'] = OxplayerStreamLog.describeUrl(finalUrl);
    out['resolvedHost'] = OxplayerStreamLog.describeHost(finalUrl);
    out['isStreamOxplayerIr'] = finalUrl.contains('stream.oxplayer.ir');
    out['isRemuxTs'] = finalUrl.contains('stream.ts');
    out['isIranVanity'] = finalUrl.contains('.ir.cdn.ir');
    out['isMkv'] = finalUrl.contains('.mkv');

    out['rangeProbe'] = kIsWeb
        ? await OxplayerPlaybackDiagHooks.probeCdnRange(finalUrl)
        : await _probeHead(finalUrl);

    if (kIsWeb) {
      out['videoProbe'] = await OxplayerPlaybackDiagHooks.probeVideoLoad(finalUrl);
    }

    return out;
  }

  Future<Map<String, Object?>> _fetchResumePlaybackUrl(String userId) async {
    final api = _ref.read(jellyApiProvider);
    try {
      final resume = await api.usersUserIdItemsResumeGet(
        limit: 8,
        mediaTypes: [MediaType.video],
        fields: [ItemFields.mediasources],
      );
      final items = resume.body?.items;
      if (items == null || items.isEmpty) {
        return {'reason': 'no_resume_items'};
      }

      for (final item in items) {
        final itemId = item.id;
        if (itemId == null || itemId.isEmpty) continue;
        final playback = await api.itemsItemIdPlaybackInfoPost(
          itemId: itemId,
          body: PlaybackInfoDto(
            userId: userId,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: false,
            autoOpenLiveStream: true,
          ),
        );
        final source = oxplayerResolvePlaybackMediaSource(playback.body);
        final path = source?.path?.trim();
        if (path != null && path.isNotEmpty && oxplayerIsOxStreamUrl(path)) {
          return {
            'itemId': itemId,
            'itemName': item.name,
            'apiMinted': path,
          };
        }
      }
      return {'reason': 'resume_items_without_ox_stream'};
    } catch (e) {
      return {'error': e.runtimeType.toString()};
    }
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
    final playbackProbe = report['playbackProbe'];
    final webHooks = report['webHooks'];
    final probes = report['probes'];

    final checks = <String, Object?>{
      'apiHealthOk': _probeOk(probes, 'health'),
      'streamNodesOk': _nodesOk(probes),
    };

    final cdnRange = probes is Map ? probes['cdnRange'] : null;
    if (cdnRange is Map) {
      final streamProbe = cdnRange[OxplayerIranStreamEdge.iranStreamOriginHost];
      if (streamProbe is Map) {
        checks['cdnRangeStreamOxplayerIrOk'] = streamProbe['ok'] == true;
      }
    }

    if (playback is Map<String, Object?>) {
      checks['playbackUsesStreamOxplayerIr'] = playback['isStreamOxplayerIr'] == true;
      checks['playbackUsesIranVanity'] = playback['isIranVanity'] == true;
      checks['playbackUsesRemuxTs'] = playback['isRemuxTs'] == true;
    }

    if (playbackProbe is Map<String, Object?>) {
      checks['playbackProbeResolvedStreamOxplayerIr'] = playbackProbe['isStreamOxplayerIr'] == true;
      checks['playbackProbeUsesRemuxTs'] = playbackProbe['isRemuxTs'] == true;
      checks['playbackProbeAvoidsIranVanity'] = playbackProbe['isIranVanity'] != true;
      checks['playbackProbeAvoidsMkv'] = playbackProbe['isMkv'] != true;
      final rangeProbe = playbackProbe['rangeProbe'];
      if (rangeProbe is Map) {
        checks['playbackProbeRangeOk'] = rangeProbe['ok'] == true;
      }
      final videoProbe = playbackProbe['videoProbe'];
      if (videoProbe is Map) {
        checks['playbackProbeVideoOk'] = videoProbe['ok'] == true;
      }
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
