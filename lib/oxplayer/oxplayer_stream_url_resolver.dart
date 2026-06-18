import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
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

/// Rewrites an API-minted ox-stream URL to a healthy discovery node host.
Future<String?> oxplayerResolveStreamPlaybackUrl(
  Ref ref,
  String? apiMintedUrl, {
  bool forceRefreshNodes = false,
}) async {
  if (!OxplayerEnv.isEnabled || apiMintedUrl == null || !oxplayerIsOxStreamUrl(apiMintedUrl)) {
    return apiMintedUrl;
  }

  final uri = Uri.tryParse(apiMintedUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return apiMintedUrl;
  }

  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) return apiMintedUrl;

  final api = ref.read(_streamNodesApiProvider);
  final nodes = await api.fetchHealthyNodes(
    accessToken: token,
    forceRefresh: forceRefreshNodes,
  );
  if (nodes.isEmpty) {
    unawaited(OxplayerPlaybackTelemetry.reportFailure(
      stage: 'stream_nodes',
      reason: 'no_healthy_nodes',
      streamUrl: apiMintedUrl,
      transient: true,
    ));
    return apiMintedUrl;
  }

  OxplayerStreamNodeSession.nodes = nodes;
  final pick = oxplayerPickRandomStreamNode(
    nodes.where((n) => !OxplayerStreamNodeSession.failedNodeIds.contains(n.id)).toList(),
  );
  if (pick == null) return apiMintedUrl;

  OxplayerStreamNodeSession.activeNodeId = pick.id;
  final nodeBase = Uri.parse(pick.url);
  return uri.replace(scheme: nodeBase.scheme, host: nodeBase.host, port: nodeBase.port).toString();
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
    OxplayerStreamNodeSession.markFailed(active);
  }

  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) return null;

  final api = ref.read(_streamNodesApiProvider);
  while (DateTime.now().isBefore(deadline)) {
    final nodes = await api.fetchHealthyNodes(
      accessToken: token,
      forceRefresh: OxplayerStreamNodeSession.nodes.isEmpty,
    );
    if (nodes.isEmpty) break;
    OxplayerStreamNodeSession.nodes = nodes;

    final next = oxplayerNextStreamNode(nodes, OxplayerStreamNodeSession.failedNodeIds);
    if (next == null) break;

    OxplayerStreamNodeSession.activeNodeId = next.id;
    final nodeBase = Uri.parse(next.url);
    return uri.replace(scheme: nodeBase.scheme, host: nodeBase.host, port: nodeBase.port).toString();
  }
  return null;
}
