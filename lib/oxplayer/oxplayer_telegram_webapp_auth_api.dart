import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_auth_http.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart'
    show OxplayerLoginAttemptException, OxplayerLoginAttemptPollResult;

/// Exchanges a TDLib-obtained Telegram Mini App `initData` payload (see
/// OxplayerTdlibBridgeController.fetchWebAppInitData) for OX session tokens via
/// `POST /auth/telegram` (oxplayer-be apps/api/internal/server/auth_telegram_webapp.go).
///
/// Same response shape as OxplayerLoginAttemptApi's poll endpoint (`X-Ox-Refresh-Token` header +
/// AuthenticationResult JSON body — both call writeJellyfinAuthenticationResult server-side), so
/// this reuses OxplayerLoginAttemptPollResult directly and the result can be handed straight to
/// oxplayerAuthenticateFromLoginAttemptPoll.
class OxplayerTelegramWebAppAuthApi {
  OxplayerTelegramWebAppAuthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<OxplayerLoginAttemptPollResult> exchangeInitData({
    required String initData,
    required String deviceId,
    String? deviceName,
  }) async {
    final response = await OxplayerAuthHttp.send(() => _client.post(
          OxplayerAuthHttp.uri('/auth/telegram'),
          headers: OxplayerAuthHttp.headers(
            extra: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          ),
          body: jsonEncode({
            'initData': initData,
            'deviceId': deviceId,
            if (deviceName != null) 'deviceName': deviceName,
          }),
        ));
    if (response.statusCode != 200) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final refresh = response.headers['x-ox-refresh-token'];
    return OxplayerLoginAttemptPollResult.completed(map, refreshToken: refresh);
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Telegram sign-in failed (${response.statusCode})';
  }
}
