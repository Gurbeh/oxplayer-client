import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/oxplayer/oxplayer_share.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/deep_link_helper.dart';

void main() {
  group('oxplayerBuildShareUrl', () {
    test('catalog id only', () {
      expect(
        oxplayerBuildShareUrl('abc-123'),
        'https://oxplayer.app/share/abc-123',
      );
    });

    test('includes mediaSourceId query param', () {
      expect(
        oxplayerBuildShareUrl('abc-123', mediaSourceId: 'ms_variant_1'),
        'https://oxplayer.app/share/abc-123?mediaSourceId=ms_variant_1',
      );
    });
  });

  group('oxplayerCatalogIdFromShareUri', () {
    test('parses https share path', () {
      final uri = Uri.parse('https://oxplayer.app/share/catalog-id-1');
      expect(oxplayerCatalogIdFromShareUri(uri), 'catalog-id-1');
    });

    test('parses custom scheme share path', () {
      final uri = Uri.parse('oxplayer:///share/catalog-id-2');
      expect(oxplayerCatalogIdFromShareUri(uri), 'catalog-id-2');
    });
  });

  group('oxplayerMediaSourceIdFromShareUri', () {
    test('reads mediaSourceId from query', () {
      final uri = Uri.parse(
        'https://oxplayer.app/share/catalog-id-1?mediaSourceId=ms_1080p',
      );
      expect(oxplayerMediaSourceIdFromShareUri(uri), 'ms_1080p');
    });

    test('reads mediaSourceId from custom scheme query', () {
      final uri = Uri.parse(
        'oxplayer:///share/catalog-id-2?mediaSourceId=ms_720p',
      );
      expect(oxplayerMediaSourceIdFromShareUri(uri), 'ms_720p');
    });
  });

  group('payloadToRoute share links', () {
    test('https production share url', () {
      final route = payloadToRoute(Uri.parse(
        'https://oxplayer.app/share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
      expect((route as DetailsRoute).queryParams.getString('id', ''), 'f55d713c-2392-4de4-87c3-d0595587b717');
    });

    test('custom scheme share url', () {
      final route = payloadToRoute(Uri.parse(
        'oxplayer:///share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
    });

    test('path-only share url', () {
      final route = payloadToRoute(Uri.parse(
        '/share/f55d713c-2392-4de4-87c3-d0595587b717',
      ));
      expect(route, isA<DetailsRoute>());
    });
  });
}
