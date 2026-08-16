import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_auth_http.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart'
    show OxplayerLoginAttemptException, OxplayerLoginAttemptPollResult;

/// A pending main-bot login attempt: [code] is what the user types into the bot (or is embedded
/// in the QR/deep-link the bot approves) — see oxplayer-be apps/api/internal/server/
/// auth_login_attempt.go's createLoginAttempt/pollLoginAttempt.
class OxplayerLoginAttemptStart {
  const OxplayerLoginAttemptStart({required this.attemptId, required this.code, required this.expiresIn});
  final String attemptId;
  final String code;
  final int expiresIn;
}

class OxplayerUserBotToken {
  const OxplayerUserBotToken({required this.token, required this.username, required this.isSessionPreferred});
  final String token;
  final String username;

  /// True when the backend's resolveDeliveryReader will deliver to the account's linked Telegram
  /// session rather than this bot — see auth_bot_token.go's readerKind. The native bridge must not
  /// be switched to bot-mode in that case: nothing would ever land in the bot's own DM.
  final bool isSessionPreferred;
}

/// Bot-token login: an alternative to TDLib phone/QR for users who don't want to give OXPlayer
/// access to their personal Telegram account. The user approves sign-in via @main-bot (typed
/// code or QR deep link) instead of logging the native Telegram bridge into their own account.
class OxplayerMainBotLoginApi {
  OxplayerMainBotLoginApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<OxplayerLoginAttemptStart> createAttempt({required String deviceId}) async {
    final response = await OxplayerAuthHttp.send(() => _client.post(
          OxplayerAuthHttp.uri('/auth/login-attempt'),
          headers: OxplayerAuthHttp.headers(
            extra: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          ),
          body: jsonEncode({'deviceId': deviceId}),
        ));
    if (response.statusCode != 201) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return OxplayerLoginAttemptStart(
      attemptId: map['attemptId'] as String,
      code: map['code'] as String,
      expiresIn: (map['expiresIn'] as num?)?.toInt() ?? 600,
    );
  }

  /// One poll round-trip — the server itself long-polls up to ~55s server-side before replying,
  /// so callers should loop this (not busy-poll faster) until it returns non-pending or throws.
  Future<OxplayerLoginAttemptPollResult> poll({
    required String attemptId,
    required String deviceId,
  }) async {
    final response = await OxplayerAuthHttp.send(() => _client.get(
          OxplayerAuthHttp.uri('/auth/login-attempt/$attemptId', {'deviceId': deviceId}),
          headers: OxplayerAuthHttp.headers(extra: {'Accept': 'application/json'}),
        ));
    if (response.statusCode != 200) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    if (map.containsKey('status')) {
      // Still {"status":"pending"} — server timed out its own long-poll window, caller re-polls.
      return const OxplayerLoginAttemptPollResult.pending();
    }
    final refresh = response.headers['x-ox-refresh-token'];
    return OxplayerLoginAttemptPollResult.completed(map, refreshToken: refresh);
  }

  /// Fetches the signed-in user's personal bot token (set via /connectbot in Telegram), to
  /// configure the native oxtelegram bridge (OxplayerTdlibBridgeController.submitBotToken).
  /// [accessToken] is the OX session's own access token — this is an authenticated GET, unlike
  /// createAttempt/poll above. Returns null if the user hasn't connected a bot yet.
  Future<OxplayerUserBotToken?> fetchUserBotToken({required String accessToken}) async {
    final response = await OxplayerAuthHttp.send(() => _client.get(
          OxplayerAuthHttp.uri('/auth/bot-token'),
          headers: OxplayerAuthHttp.headers(extra: {
            'Accept': 'application/json',
            'Authorization': 'Mediabrowser Token="$accessToken"',
          }),
        ));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return OxplayerUserBotToken(
      token: map['botToken'] as String,
      username: map['botUsername'] as String,
      isSessionPreferred: map['readerKind'] == 'session',
    );
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Bot sign-in failed (${response.statusCode})';
  }
}
