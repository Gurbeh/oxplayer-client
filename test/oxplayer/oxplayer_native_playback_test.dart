import 'package:fladder/oxplayer/oxplayer_native_playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('oxplayerNativePlaybackLooksStuck', () {
    test('not stuck while buffering', () {
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: false,
          buffering: true,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isFalse,
      );
    });

    test('not stuck when playing', () {
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: true,
          buffering: false,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isFalse,
      );
    });

    test('not stuck when buffer advanced', () {
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: Duration.zero,
          buffer: const Duration(seconds: 5),
        ),
        isFalse,
      );
    });

    test('stuck when idle at start with no buffer', () {
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: Duration.zero,
          buffer: Duration.zero,
        ),
        isTrue,
      );
    });

    test('respects resume start position', () {
      const start = Duration(minutes: 10);
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: start,
          buffer: Duration.zero,
          startPosition: start,
        ),
        isTrue,
      );
      expect(
        oxplayerNativePlaybackLooksStuck(
          playing: false,
          buffering: false,
          position: start + const Duration(seconds: 5),
          buffer: Duration.zero,
          startPosition: start,
        ),
        isFalse,
      );
    });
  });
}
