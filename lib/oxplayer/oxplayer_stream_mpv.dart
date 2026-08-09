import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// HTTP progressive ox-stream MKV (not remux TS).
bool oxplayerStreamDirectMkvUrl(String url) {
  if (!OxplayerEnv.isEnabled || !oxplayerIsOxStreamUrl(url)) return false;
  return !url.contains('/stream.ts') && !url.contains('stream.ts?');
}

/// Progressive byte-range sources that must not get MPV's short reopen-retry loop.
/// Includes Telegram loopback HTTP bridge (gotd) — same seek/buffer semantics as ox-stream MKV.
bool oxplayerStreamProgressiveHttpUrl(String url) {
  if (!OxplayerEnv.isEnabled) return false;
  return oxplayerStreamDirectMkvUrl(url) || oxplayerIsTdlibHttpBridgeUrl(url);
}

/// Large client-side resume/seek on progressive HTTP needs long MPV load grace.
bool oxplayerStreamMpvResumeSeekGrace(String url, Duration startPosition) {
  return oxplayerStreamProgressiveHttpUrl(url) &&
      startPosition > const Duration(seconds: 30);
}

/// MPV must not reopen the HTTP read while ExoPlayer/mpv is still seeking (Iran CDN).
const oxplayerStreamMpvResumeRetryInterval = Duration(seconds: 90);

/// Upper bound before MPV gives up and runs ox-stream failover / force-repair.
const oxplayerStreamMpvResumeMaxRetry = Duration(minutes: 4);

/// Fallback [onReady] when duration stays 0 during CDN resume seek.
const oxplayerStreamMpvResumeReadyTimeout = Duration(seconds: 90);

/// Default ox-stream / remux ready timeout.
const oxplayerStreamMpvDefaultReadyTimeout = Duration(seconds: 12);
