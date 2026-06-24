import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_image_auth.dart';

/// Adds Jellyfin session auth to cached image fetches against the OX API (e.g. Seerr avatarproxy).
class OxplayerAuthFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final merged = Map<String, String>.from(headers ?? {});
    if (OxplayerEnv.isEnabled && _needsAuth(url)) {
      final token = OxplayerImageAuth.accessToken;
      if (token != null && token.isNotEmpty) {
        merged.putIfAbsent(
          'authorization',
          () => 'MediaBrowser Token="$token"',
        );
      }
    }
    return super.get(url, headers: merged);
  }

  bool _needsAuth(String url) {
    return url.toLowerCase().contains('/seerr/proxy/');
  }
}
