import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';

/// Resolves a PlaybackInfo-minted URL to a playable one. Telegram-native links resolve via the
/// device's own TDLib session; any other URL (e.g. the store-review test account's direct demo
/// clip) is returned unchanged — there's no CDN/proxy layer left to rewrite it through.
Future<String?> oxplayerResolveStreamPlaybackUrl(
  OxplayerRead read,
  String? apiMintedUrl, {
  bool forceRefreshNodes = false,
}) async {
  if (!oxplayerIsTelegramProviderLink(apiMintedUrl)) {
    return apiMintedUrl;
  }

  final wantedPlayer = read(videoPlayerSettingsProvider).wantedPlayer;
  // TEMP (Windows bridge parity test): prefer HTTP bridge + libmpv on all platforms,
  // including Android. Product default was Android → tdlib-file:// + Exo; restore later
  // by gating Android to preferHttpBridge=false again. gotd-only either way.
  final useHttpBridge = wantedPlayer != PlayerOptions.nativePlayer;
  return oxplayerResolveTdlibPlaybackUrl(
    apiMintedUrl!,
    preferHttpBridge: useHttpBridge,
  );
}
