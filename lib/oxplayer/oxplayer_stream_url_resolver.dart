import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_http_auth.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// Session-scoped stream node selection state for a single playback.
class OxplayerStreamNodeSession {
  static final Set<int> failedNodeIds = <int>{};
  static int? activeNodeId;
  static List<OxplayerStreamNode> nodes = const [];

  static void reset() {
    failedNodeIds.clear();
    activeNodeId = null;
    nodes = const [];
  }

  static void markFailed(int nodeId) {
    failedNodeIds.add(nodeId);
  }
}

final _streamNodesApiProvider = Provider<OxplayerStreamNodesApi>((ref) => OxplayerStreamNodesApi());

/// Applies Iran CDN vanity / edge pin — independent of stream-node discovery.
String _finalizeStreamPlaybackUrl(String url, {required String via}) {
  final out = OxplayerRoute.rewriteStreamUri(url);
  if (out != url) {
    OxplayerStreamLog.event('resolve_finalize', fields: {
      'via': via,
      'before': OxplayerStreamLog.describeUrl(url),
      'after': OxplayerStreamLog.describeUrl(out),
      'finalHost': OxplayerStreamLog.describeHost(out),
    });
  } else if (OxplayerRoute.active == OxplayerEdge.iran) {
    OxplayerStreamLog.event('resolve_finalize_noop', fields: {
      'via': via,
      'url': OxplayerStreamLog.describeUrl(url),
      'streamVanity': OxplayerRoute.streamBaseUrl,
      'edge': OxplayerRoute.active.name,
    });
  }
  OxplayerStreamLog.probeRangeAsync(out);
  return OxplayerStreamHttpAuth.stripAndRegister(out);
}

/// Iran cohort: rewrite global stream host → CDN.ir before node discovery.
String _iranVanityEarly(String url) {
  if (OxplayerRoute.active != OxplayerEdge.iran) return url;
  final out = OxplayerRoute.rewriteStreamUri(url);
  if (out != url) {
    OxplayerStreamLog.event('resolve_iran_vanity_early', fields: {
      'before': OxplayerStreamLog.describeUrl(url),
      'after': OxplayerStreamLog.describeUrl(out),
    });
  }
  return out;
}

/// Rewrites an API-minted ox-stream URL to a healthy discovery node host.
Future<String?> oxplayerResolveStreamPlaybackUrl(
  Ref ref,
  String? apiMintedUrl, {
  bool forceRefreshNodes = false,
}) async {
  if (!OxplayerEnv.isEnabled || apiMintedUrl == null || !oxplayerIsOxStreamUrl(apiMintedUrl)) {
    OxplayerStreamLog.event('resolve_skip', fields: {
      'reason': apiMintedUrl == null ? 'null_url' : 'not_ox_stream',
      'url': OxplayerStreamLog.describeUrl(apiMintedUrl),
    });
    return apiMintedUrl;
  }

  OxplayerStreamLog.routeContext();
  OxplayerStreamLog.event('resolve_enter', fields: {
    'apiMinted': OxplayerStreamLog.describeUrl(apiMintedUrl),
    'apiMintedHost': OxplayerStreamLog.describeHost(apiMintedUrl),
  });

  OxplayerStreamHttpAuth.clear();

  var workingUrl = _iranVanityEarly(apiMintedUrl);

  final uri = Uri.tryParse(workingUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return _finalizeStreamPlaybackUrl(workingUrl, via: 'invalid_uri');
  }

  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) {
    return _finalizeStreamPlaybackUrl(workingUrl, via: 'no_token');
  }

  final base = ref.read(serverUrlProvider)?.trim() ?? '';
  if (base.isEmpty) {
    return _finalizeStreamPlaybackUrl(workingUrl, via: 'no_api_base');
  }

  final api = ref.read(_streamNodesApiProvider);
  final nodes = await api.fetchHealthyNodes(
    baseUrl: base,
    accessToken: token,
    forceRefresh: forceRefreshNodes,
  );
  if (nodes.isEmpty) {
    OxplayerStreamLog.event('resolve_no_nodes', fields: {
      'apiMinted': OxplayerStreamLog.describeUrl(apiMintedUrl),
      'iranVanity': OxplayerRoute.streamBaseUrl,
    });
    unawaited(OxplayerPlaybackTelemetry.reportFailure(
      stage: 'stream_nodes',
      reason: 'no_healthy_nodes',
      streamUrl: apiMintedUrl,
      transient: true,
    ));
    return _finalizeStreamPlaybackUrl(workingUrl, via: 'no_nodes');
  }

  OxplayerStreamNodeSession.nodes = nodes;
  final pick = oxplayerPickRandomStreamNode(
    nodes.where((n) => !OxplayerStreamNodeSession.failedNodeIds.contains(n.id)).toList(),
  );
  if (pick == null) {
    return _finalizeStreamPlaybackUrl(workingUrl, via: 'no_pick');
  }

  OxplayerStreamNodeSession.activeNodeId = pick.id;
  final nodeBase = Uri.parse(pick.url);
  final rewritten = uri
      .replace(scheme: nodeBase.scheme, host: nodeBase.host, port: nodeBase.port)
      .toString();
  final finalUrl = _finalizeStreamPlaybackUrl(rewritten, via: 'node_${pick.id}');
  OxplayerStreamLog.event('resolve_ok', fields: {
    'nodeId': pick.id,
    'nodeUrl': OxplayerStreamLog.describeUrl(pick.url),
    'afterNodeRewrite': OxplayerStreamLog.describeUrl(rewritten),
    'finalUrl': OxplayerStreamLog.describeUrl(finalUrl),
    'finalHost': OxplayerStreamLog.describeHost(finalUrl),
  });
  return finalUrl;
}

/// Failover to the next healthy node within [budget], rewriting [currentUrl]'s host.
Future<String?> oxplayerFailoverStreamUrl(
  Ref ref,
  String currentUrl, {
  Duration budget = const Duration(milliseconds: 1500),
}) async {
  if (!OxplayerEnv.isEnabled || !oxplayerIsOxStreamUrl(currentUrl)) return null;

  final deadline = DateTime.now().add(budget);
  final uri = Uri.tryParse(currentUrl);
  if (uri == null) return null;

  final active = OxplayerStreamNodeSession.activeNodeId;
  if (active != null) {
    OxplayerStreamLog.event('failover_attempt', fields: {'activeNodeId': active});
  }

  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) return null;

  final base = ref.read(serverUrlProvider)?.trim() ?? '';
  if (base.isEmpty) return null;

  final api = ref.read(_streamNodesApiProvider);
  while (DateTime.now().isBefore(deadline)) {
    final nodes = await api.fetchHealthyNodes(
      baseUrl: base,
      accessToken: token,
      forceRefresh: OxplayerStreamNodeSession.nodes.isEmpty,
    );
    if (nodes.isEmpty) break;
    OxplayerStreamNodeSession.nodes = nodes;

    final next = oxplayerNextStreamNode(nodes, OxplayerStreamNodeSession.failedNodeIds);
    if (next == null) break;

    OxplayerStreamNodeSession.activeNodeId = next.id;
    final nodeBase = Uri.parse(next.url);
    final rewritten = uri
        .replace(scheme: nodeBase.scheme, host: nodeBase.host, port: nodeBase.port)
        .toString();
    final out = OxplayerRoute.rewriteStreamUri(rewritten);
    if (out == currentUrl) {
      OxplayerStreamLog.event('failover_skip_same_url', fields: {
        'nodeId': next.id,
        'url': OxplayerStreamLog.describeUrl(out),
      });
      OxplayerStreamNodeSession.markFailed(next.id);
      continue;
    }
    if (active != null) {
      OxplayerStreamNodeSession.markFailed(active);
    }
    OxplayerStreamLog.event('failover_ok', fields: {
      'nodeId': next.id,
      'finalUrl': OxplayerStreamLog.describeUrl(out),
    });
    return OxplayerStreamHttpAuth.stripAndRegister(out);
  }
  final fallback = _finalizeStreamPlaybackUrl(currentUrl, via: 'failover_vanity');
  if (fallback != currentUrl) {
    if (active != null) {
      OxplayerStreamNodeSession.markFailed(active);
    }
    OxplayerStreamLog.event('failover_vanity', fields: {
      'finalUrl': OxplayerStreamLog.describeUrl(fallback),
    });
    return fallback;
  }
  OxplayerStreamLog.event('failover_exhausted', fields: {
    'currentUrl': OxplayerStreamLog.describeUrl(currentUrl),
  });
  if (active != null) {
    OxplayerStreamNodeSession.markFailed(active);
  }
  return null;
}
