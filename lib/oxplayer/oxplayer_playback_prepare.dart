import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/video_player_provider.dart';

/// Yields one frame so the preparing-playback dialog can paint before LibMPV/MediaKit init.
Future<void> oxplayerInitVideoPlayerIfNeeded(WidgetRef ref) async {
  await Future<void>.delayed(Duration.zero);
  await ref.read(videoPlayerProvider.notifier).init();
}
