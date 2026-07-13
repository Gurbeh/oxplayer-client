import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/oxplayer/oxplayer_iran_stream_edge.dart';

void main() {
  group('OxplayerIranStreamEdge', () {
    test('isIranVanityStreamUrl matches CDN.ir vanity and edge hosts', () {
      expect(
        OxplayerIranStreamEdge.isIranVanityStreamUrl('https://oxstream.256251.ir.cdn.ir/v/1.mkv'),
        isTrue,
      );
      expect(
        OxplayerIranStreamEdge.isIranVanityStreamUrl('https://edge01.256251.ir.cdn.ir/v/1.mkv'),
        isTrue,
      );
      expect(
        OxplayerIranStreamEdge.isIranVanityStreamUrl('https://stream.oxplayer.ir/v/1.mkv'),
        isFalse,
      );
    });

    test('rewriteWebPlaybackUrl is a no-op off-web', () {
      const mkv = 'https://stream.oxplayer.ir/v/900017099.mkv?token=abc';
      expect(OxplayerIranStreamEdge.rewriteWebPlaybackUrl(mkv), mkv);
    });
  });
}
