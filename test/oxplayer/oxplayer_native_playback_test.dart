import 'package:fladder/oxplayer/oxplayer_stuck_playback.dart';
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

  group('oxplayerPlaybackLooksFrozenMidStream', () {
    const start = Duration(minutes: 5);
    const mid = Duration(minutes: 15);

    test('not frozen while buffering', () {
      expect(
        oxplayerPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: true,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('not frozen when paused', () {
      expect(
        oxplayerPlaybackLooksFrozenMidStream(
          playing: false,
          buffering: false,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('not frozen when position advanced', () {
      expect(
        oxplayerPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: mid + const Duration(seconds: 3),
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          startPosition: start,
        ),
        isFalse,
      );
    });

    test('frozen when playing but timeline stalled mid-stream', () {
      expect(
        oxplayerPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: mid,
          previousPosition: mid,
          buffer: mid,
          previousBuffer: mid,
          duration: const Duration(hours: 2),
          startPosition: start,
        ),
        isTrue,
      );
    });

    test('not frozen near end credits', () {
      const duration = Duration(hours: 2);
      expect(
        oxplayerPlaybackLooksFrozenMidStream(
          playing: true,
          buffering: false,
          position: duration - const Duration(seconds: 5),
          previousPosition: duration - const Duration(seconds: 5),
          buffer: duration,
          previousBuffer: duration,
          duration: duration,
          startPosition: start,
        ),
        isFalse,
      );
    });
  });

  group('OxplayerStuckPlaybackTracker', () {
    test('resume grace blocks immediate mid-stream false positive after pause', () {
      final tracker = OxplayerStuckPlaybackTracker();
      final now = DateTime(2026, 7, 6);
      const mid = Duration(hours: 2);

      tracker.onPlaybackSample(
        playing: false,
        position: mid,
        buffer: mid,
        now: now,
      );
      tracker.advanceSample(position: mid, buffer: mid);

      tracker.onPlaybackSample(
        playing: true,
        position: mid,
        buffer: mid,
        now: now.add(const Duration(seconds: 1)),
      );

      expect(tracker.inResumeGrace(now.add(const Duration(seconds: 1))), isTrue);
      expect(
        tracker.noteMidStreamFrozenSample(
          oxplayerPlaybackLooksFrozenMidStream(
            playing: true,
            buffering: false,
            position: mid,
            previousPosition: mid,
            buffer: mid,
            previousBuffer: mid,
            duration: const Duration(hours: 3),
          ),
        ),
        isFalse,
      );
    });

    test('requires consecutive frozen samples after grace expires', () {
      final tracker = OxplayerStuckPlaybackTracker();
      const mid = Duration(hours: 2);

      expect(
        tracker.noteMidStreamFrozenSample(true),
        isFalse,
      );
      expect(
        tracker.noteMidStreamFrozenSample(true),
        isTrue,
      );
      expect(
        tracker.noteMidStreamFrozenSample(false),
        isFalse,
      );
    });
  });
}
