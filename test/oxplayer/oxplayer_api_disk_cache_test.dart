import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_api_disk_cache.dart';
import 'package:fladder/oxplayer/oxplayer_swr_http_client.dart';

void main() {
  test('OxplayerApiDiskCache.key is stable and user-scoped', () {
    final uri = Uri.parse('https://api.example/Users/u1/Home/Feed?limit=16');
    final a = OxplayerApiDiskCache.key(userId: 'u1', method: 'GET', uri: uri);
    final b = OxplayerApiDiskCache.key(userId: 'u1', method: 'get', uri: uri);
    final c = OxplayerApiDiskCache.key(userId: 'u2', method: 'GET', uri: uri);
    expect(a, b);
    expect(a, isNot(c));
    expect(a.length, 16);
  });

  test('oxSwrShouldCacheRequest allowlist skips playback and auth', () {
    expect(
      oxSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Users/1/Views'))),
      isTrue,
    );
    expect(
      oxSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Shows/abc/Seasons'))),
      isTrue,
    );
    expect(
      oxSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Shows/abc/Episodes'))),
      isTrue,
    );
    expect(
      oxSwrShouldCacheRequest(http.Request('GET', Uri.parse('https://x/Items/abc/PlaybackInfo'))),
      isFalse,
    );
    expect(
      oxSwrShouldCacheRequest(http.Request('POST', Uri.parse('https://x/Items'))),
      isFalse,
    );
  });
}
