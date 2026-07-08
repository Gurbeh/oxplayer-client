import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';
import 'package:fladder/providers/api_provider.dart';

/// TMDB-relative or absolute image path → display URL for Seerr UI.
///
/// In OX mode, images load via `{apiBase}/tmdb/image/{size}/…` so posters work
/// through the API domain (auth, ngrok, LAN). Upstream Fladder TMDB concat is unchanged.
String? oxSeerrPosterUrl(String? path) =>
    _resolve(path, fladderBase: 'https://image.tmdb.org/t/p/w500', oxSize: 'w500');

String? oxSeerrBackdropUrl(String? path) =>
    _resolve(path, fladderBase: 'https://image.tmdb.org/t/p/original', oxSize: 'original');

String? oxSeerrProfileUrl(String? path) =>
    _resolve(path, fladderBase: 'https://image.tmdb.org/t/p/w185', oxSize: 'w185');

String? oxSeerrStillUrl(String? path) =>
    _resolve(path, fladderBase: 'https://image.tmdb.org/t/p/original', oxSize: 'original');

String? oxSeerrLogoUrl(String? path) =>
    _resolve(path, fladderBase: 'https://image.tmdb.org/t/p/original', oxSize: 'original');

String? _resolve(String? path, {required String fladderBase, required String oxSize}) {
  if (path == null || path.isEmpty) return null;

  if (!OxplayerConfig.isEnabled) {
    return '$fladderBase$path';
  }

  final trimmed = path.trim();
  if (hasHttpScheme(trimmed)) return trimmed;

  final api = OxplayerRoute.apiBaseUrl ?? OxplayerEnv.apiBaseUrl;
  if (api == null || api.isEmpty) {
    return '$fladderBase$path';
  }

  final filePath = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
  return '$api/tmdb/image/$oxSize/$filePath';
}
