import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// Progressive byte-range sources that must not get MPV's short reopen-retry loop.
/// Telegram direct-play (gotd) via either transport — loopback HTTP bridge or (Windows) stream_cb.
bool oxplayerStreamProgressiveHttpUrl(String url) {
  if (!OxplayerEnv.isEnabled) return false;
  return oxplayerIsTelegramDirectPlayUrl(url);
}

/// Large client-side resume/seek on progressive HTTP needs long MPV load grace.
bool oxplayerStreamMpvResumeSeekGrace(String url, Duration startPosition) {
  return oxplayerStreamProgressiveHttpUrl(url) &&
      startPosition > const Duration(seconds: 30);
}

/// MPV must not reopen the HTTP read while ExoPlayer/mpv is still seeking.
const oxplayerStreamMpvResumeRetryInterval = Duration(seconds: 90);

/// Upper bound before MPV gives up and runs force-repair.
const oxplayerStreamMpvResumeMaxRetry = Duration(minutes: 4);

/// Fallback [onReady] when duration stays 0 during resume seek.
const oxplayerStreamMpvResumeReadyTimeout = Duration(seconds: 90);

/// Default progressive-playback ready timeout.
const oxplayerStreamMpvDefaultReadyTimeout = Duration(seconds: 12);
