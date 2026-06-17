import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/oxplayer/oxplayer_stream_nodes_api.dart';

void main() {
  group('oxplayerNextStreamNode', () {
    test('skips failed ids in order', () {
      final nodes = [
        const OxplayerStreamNode(id: 1, url: 'https://stream-01.test'),
        const OxplayerStreamNode(id: 2, url: 'https://stream-02.test'),
        const OxplayerStreamNode(id: 3, url: 'https://stream-03.test'),
      ];
      final next = oxplayerNextStreamNode(nodes, {1});
      expect(next?.id, 2);
      expect(oxplayerNextStreamNode(nodes, {1, 2})?.id, 3);
      expect(oxplayerNextStreamNode(nodes, {1, 2, 3}), isNull);
    });
  });

  group('OxplayerStreamNodesResponse', () {
    test('parses nodes array', () {
      final resp = OxplayerStreamNodesResponse.fromJson({
        'nodes': [
          {'id': 1, 'url': 'https://stream-01.oxplayer.app'},
          {'id': 2, 'url': 'https://stream-02.oxplayer.app'},
        ],
      });
      expect(resp.nodes, hasLength(2));
      expect(resp.nodes.first.id, 1);
    });
  });
}
