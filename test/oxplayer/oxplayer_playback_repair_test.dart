import 'package:fladder/oxplayer/oxplayer_force_repair_interceptor.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('oxplayerIsOxStreamUrl', () {
    test('detects ox-stream remux URLs', () {
      expect(oxplayerIsOxStreamUrl('https://stream.example/v/1/stream.ts?jwt=abc'), isTrue);
      expect(oxplayerIsOxStreamUrl('https://stream.example/stream.ts'), isTrue);
      expect(oxplayerIsOxStreamUrl('https://cdn.example/video.mp4'), isFalse);
      expect(oxplayerIsOxStreamUrl(null), isFalse);
    });
  });

  group('force repair single-shot flag', () {
    test('arms via provider and clears after use', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(oxplayerForceRepairNextPlaybackProvider), isFalse);
      container.read(oxplayerForceRepairNextPlaybackProvider.notifier).state = true;
      expect(container.read(oxplayerForceRepairNextPlaybackProvider), isTrue);

      // Interceptor clears after a armed PlaybackInfo call; simulate that clear.
      container.read(oxplayerForceRepairNextPlaybackProvider.notifier).state = false;
      expect(container.read(oxplayerForceRepairNextPlaybackProvider), isFalse);
    });

    test('header name is stable', () {
      expect(oxplayerForceRepairHeader, 'X-OX-Force-Repair');
    });
  });

  group('OxplayerStreamRepairBridge', () {
    test('runtime repair is single-shot', () {
      OxplayerStreamRepairBridge.runtimeRepairUsed = false;
      OxplayerStreamRepairBridge.runtimeRepairUsed = true;
      expect(OxplayerStreamRepairBridge.runtimeRepairUsed, isTrue);
      OxplayerStreamRepairBridge.clear();
      expect(OxplayerStreamRepairBridge.runtimeRepairUsed, isFalse);
    });
  });
}
