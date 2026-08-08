import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_iran_stream_edge.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_warmup.dart';
import 'package:fladder/oxplayer/oxplayer_stream_http_auth.dart';
import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
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

/// Applies Iran stream vanity / edge pin — independent of stream-node discovery.
Future<String> _finalizeStreamPlaybackUrl(String url, {required String via}) async {
  var out = kIsWeb ? url : OxplayerRoute.rewriteStreamUri(url);
  if (OxplayerIranStreamEdge.isIranVanityStreamUrl(out)) {
    out = await OxplayerIranStreamEdge.resolvePlaybackUrl(out);
  }
  if (kIsWeb && oxplayerIsOxStreamUrl(out)) {
    out = OxplayerIranStreamEdge.rewriteWebPlaybackUrl(out);
  }
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
  unawaited(oxplayerWarmStreamUrl(out));
  return OxplayerStreamHttpAuth.stripAndRegister(out);
}

/// Iran cohort: rewrite global stream host → Iran vanity before node discovery.
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
  OxplayerRead read,
  String? apiMintedUrl, {
  bool forceRefreshNodes = false,
}) async {
  // MTProto direct play: PlaybackInfo returned a t.me/{username}/{messageId} link instead of an
  // ox-stream URL (TELEGRAM_NATIVE_PLAYBACK_ENABLED on the backend). Bytes come from the device's
  // own TDLib session, not ox-stream — none of the node discovery/warmup/instrumentation below
  // applies, so this returns early rather than falling through to _finalizeStreamPlaybackUrl.
  if (oxplayerIsTelegramProviderLink(apiMintedUrl)) {
    final wantedPlayer = read(videoPlayerSettingsProvider).wantedPlayer;
    return oxplayerResolveTdlibPlaybackUrl(
      apiMintedUrl!,
      preferHttpBridge: wantedPlayer != PlayerOptions.nativePlayer,
    );
  }

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
  OxplayerIranStreamEdge.clearCache();

  var workingUrl = _iranVanityEarly(apiMintedUrl);

  // Web: skip CDN.ir node discovery — browser needs stream.oxplayer.ir (CORS + no vanity redirect).
  if (kIsWeb) {
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'web_direct');
  }

  // Global cohort: the API mints the single vanity host (stream.oxplayer.app).
  // Cloudflare distributes across origin nodes (DNS round-robin) and all viewers
  // share one edge cache face, so skip per-node host rewrite. Iran keeps its
  // node/edge-pin rewrite path below.
  if (OxplayerRoute.active != OxplayerEdge.iran) {
    OxplayerStreamLog.event('resolve_vanity_cdn', fields: {
      'url': OxplayerStreamLog.describeUrl(workingUrl),
      'host': OxplayerStreamLog.describeHost(workingUrl),
    });
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'vanity_cdn');
  }

  final uri = Uri.tryParse(workingUrl);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'invalid_uri');
  }

  final token = read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) {
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'no_token');
  }

  final base = read(serverUrlProvider)?.trim() ?? '';
  if (base.isEmpty) {
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'no_api_base');
  }

  final api = read(_streamNodesApiProvider);
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
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'no_nodes');
  }

  OxplayerStreamNodeSession.nodes = nodes;
  final pick = oxplayerPickRandomStreamNode(
    nodes.where((n) => !OxplayerStreamNodeSession.failedNodeIds.contains(n.id)).toList(),
  );
  if (pick == null) {
    return await _finalizeStreamPlaybackUrl(workingUrl, via: 'no_pick');
  }

  OxplayerStreamNodeSession.activeNodeId = pick.id;
  final nodeBase = Uri.parse(pick.url);
  final rewritten = uri
      .replace(scheme: nodeBase.scheme, host: nodeBase.host, port: nodeBase.port)
      .toString();
  final finalUrl = await _finalizeStreamPlaybackUrl(rewritten, via: 'node_${pick.id}');
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
  OxplayerRead read,
  String currentUrl, {
  Duration budget = const Duration(milliseconds: 1500),
}) async {
  // oxplayerIsOxStreamUrl is false for tdlib-file:// and t.me/... urls, so this already
  // short-circuits for MTProto direct play without a separate guard: node-based failover has no
  // meaning there — retry belongs inside TdlibFileFetcher (TDLib's own flood-wait/CDN handling),
  // not this stream-node selection path.
  if (!OxplayerEnv.isEnabled || !oxplayerIsOxStreamUrl(currentUrl)) return null;
  if (kIsWeb) return null;

  final deadline = DateTime.now().add(budget);
  final uri = Uri.tryParse(currentUrl);
  if (uri == null) return null;

  final active = OxplayerStreamNodeSession.activeNodeId;
  if (active != null) {
    OxplayerStreamLog.event('failover_attempt', fields: {'activeNodeId': active});
  }

  final token = read(userProvider)?.credentials.token.trim() ?? '';
  if (token.isEmpty) return null;

  final base = read(serverUrlProvider)?.trim() ?? '';
  if (base.isEmpty) return null;

  final api = read(_streamNodesApiProvider);
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
    final out = await _finalizeStreamPlaybackUrl(
      OxplayerRoute.rewriteStreamUri(rewritten),
      via: 'failover_${next.id}',
    );
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
    return out;
  }
  final fallback = await _finalizeStreamPlaybackUrl(currentUrl, via: 'failover_vanity');
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
