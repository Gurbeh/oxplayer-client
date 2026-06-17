import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';

class OxplayerStreamNode {
  const OxplayerStreamNode({required this.id, required this.url});

  final int id;
  final String url;

  factory OxplayerStreamNode.fromJson(Map<String, dynamic> json) {
    return OxplayerStreamNode(
      id: (json['id'] as num).toInt(),
      url: (json['url'] as String).trim(),
    );
  }
}

class OxplayerStreamNodesResponse {
  const OxplayerStreamNodesResponse(this.nodes);

  final List<OxplayerStreamNode> nodes;

  factory OxplayerStreamNodesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['nodes'];
    if (raw is! List) {
      return const OxplayerStreamNodesResponse([]);
    }
    return OxplayerStreamNodesResponse(
      raw
          .whereType<Map<String, dynamic>>()
          .map(OxplayerStreamNode.fromJson)
          .where((n) => n.url.isNotEmpty)
          .toList(),
    );
  }
}

class OxplayerStreamNodesApi {
  OxplayerStreamNodesApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static List<OxplayerStreamNode>? _cache;
  static DateTime? _cacheAt;
  static const _cacheTtl = Duration(seconds: 30);

  Future<List<OxplayerStreamNode>> fetchHealthyNodes({
    required String accessToken,
    bool forceRefresh = false,
  }) async {
    if (!OxplayerEnv.isEnabled) return const [];

    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < _cacheTtl) {
      return List<OxplayerStreamNode>.from(_cache!);
    }

    final base = OxplayerEnv.apiBaseUrl;
    if (base == null || base.isEmpty || accessToken.trim().isEmpty) {
      return const [];
    }

    final uri = Uri.parse('$base/api/v1/stream/nodes');
    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'MediaBrowser Token="${accessToken.trim()}"',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      return _cache ?? const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return _cache ?? const [];
    }
    final nodes = OxplayerStreamNodesResponse.fromJson(decoded).nodes;
    _cache = List<OxplayerStreamNode>.from(nodes);
    _cacheAt = now;
    return nodes;
  }

  static void invalidateCache() {
    _cache = null;
    _cacheAt = null;
  }
}

/// Picks a random node from [nodes] (API may already shuffle; client randomizes again).
OxplayerStreamNode? oxplayerPickRandomStreamNode(List<OxplayerStreamNode> nodes) {
  if (nodes.isEmpty) return null;
  if (nodes.length == 1) return nodes.first;
  return nodes[Random().nextInt(nodes.length)];
}

/// Returns the next node not in [failedIds], preserving API order for failover rotation.
OxplayerStreamNode? oxplayerNextStreamNode(
  List<OxplayerStreamNode> nodes,
  Set<int> failedIds,
) {
  for (final node in nodes) {
    if (!failedIds.contains(node.id)) {
      return node;
    }
  }
  return null;
}
