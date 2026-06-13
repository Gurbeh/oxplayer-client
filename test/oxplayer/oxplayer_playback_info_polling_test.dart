import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_playback_info_polling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('oxplayerPlaybackHydrateRetryAfterSeconds', () {
    test('prefers Retry-After header', () {
      final response = Response<PlaybackInfoResponse>(
        http.Response('{"retry_after": 99}', 202, headers: {'retry-after': '3'}),
        null,
      );
      expect(oxplayerPlaybackHydrateRetryAfterSeconds(response), 3);
    });

    test('falls back to JSON retry_after', () {
      final response = Response<PlaybackInfoResponse>(
        http.Response('{"status":"preparing","retry_after":7}', 202),
        null,
      );
      expect(oxplayerPlaybackHydrateRetryAfterSeconds(response), 7);
    });

    test('defaults when header and body are missing', () {
      final response = Response<PlaybackInfoResponse>(
        http.Response('', 202),
        null,
      );
      expect(oxplayerPlaybackHydrateRetryAfterSeconds(response), oxplayerPlaybackHydrateRetryAfterDefaultSec);
    });
  });

  group('oxplayerPollPlaybackInfoUntilReady', () {
    test('retries on 202 then returns 200', () async {
      var calls = 0;
      final result = await oxplayerPollPlaybackInfoUntilReady(() async {
        calls++;
        if (calls < 3) {
          return Response<PlaybackInfoResponse>(
            http.Response('{"status":"preparing","retry_after":1}', 202),
            null,
          );
        }
        return Response<PlaybackInfoResponse>(
          http.Response('{}', 200),
          const PlaybackInfoResponse(playSessionId: 'ready'),
        );
      });

      expect(calls, 3);
      expect(result.statusCode, 200);
      expect(result.body?.playSessionId, 'ready');
    });

    test('returns 503 without further polling', () async {
      var calls = 0;
      final result = await oxplayerPollPlaybackInfoUntilReady(() async {
        calls++;
        return Response<PlaybackInfoResponse>(
          http.Response('unavailable', 503),
          null,
        );
      });

      expect(calls, 1);
      expect(result.statusCode, 503);
    });
  });
}
