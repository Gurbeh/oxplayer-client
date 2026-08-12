import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/util/duration_extensions.dart';

/// Matches server [DerivePlaybackPersistState] / Fladder [UserData.isPlayed].
UserData oxDerivePlaybackUserData({
  required UserData current,
  required Duration position,
  required Duration runTime,
}) {
  final playedFlag = UserData.isPlayed(position, runTime);
  if (playedFlag == null) {
    return current.copyWith(
      playbackPositionTicks: 0,
      progress: 0,
      played: false,
      lastPlayed: DateTime.now(),
    );
  }
  if (playedFlag) {
    return current.copyWith(
      playbackPositionTicks: 0,
      progress: 0,
      played: true,
      playCount: current.playCount + (current.played ? 0 : 1),
      lastPlayed: DateTime.now(),
    );
  }
  final ticks = position.toRuntimeTicks;
  final progress = runTime.inMilliseconds > 0
      ? (position.inMilliseconds / runTime.inMilliseconds * 100).clamp(0.0, 100.0)
      : 0.0;
  return current.copyWith(
    playbackPositionTicks: ticks,
    progress: progress,
    played: false,
    lastPlayed: DateTime.now(),
  );
}
