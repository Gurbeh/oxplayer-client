import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';

/// HTTP for pre-login auth endpoints (/auth/*).
abstract final class OxplayerAuthHttp {
  static String? get baseUrl => OxplayerEnv.apiBaseUrl;

  static Map<String, String> headers({Map<String, String>? extra}) => {...?extra};

  static Uri uri(String path, [Map<String, String>? query]) {
    final base = baseUrl;
    if (base == null) {
      throw StateError('OXPLAYER API base is not configured');
    }
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  static Future<http.Response> send(Future<http.Response> Function() request) {
    return request().timeout(kOxSessionRestoreTimeout);
  }
}
