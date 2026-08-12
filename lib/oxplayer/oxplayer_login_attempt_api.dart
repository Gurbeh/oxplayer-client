/// Shared auth response wrapper for Telegram Mini App / TDLib login.
///
/// Used by `OxplayerTelegramWebAppAuthApi.exchangeInitData` (POST `/auth/telegram`) and applied via
/// `oxplayerAuthenticateFromLoginAttemptPoll`. Names are historical — this is **not** a bot
/// `/auth/login-attempt` poll client. Keep [OxplayerLoginAttemptPollResult] /
/// [OxplayerLoginAttemptException]; both are still used by the TDLib webapp path.
class OxplayerLoginAttemptPollResult {
  const OxplayerLoginAttemptPollResult._({this.jellyfinBody, this.refreshToken});

  const OxplayerLoginAttemptPollResult.pending() : this._();

  const OxplayerLoginAttemptPollResult.completed(
    Map<String, dynamic> body, {
    String? refreshToken,
  }) : this._(jellyfinBody: body, refreshToken: refreshToken);

  final Map<String, dynamic>? jellyfinBody;
  final String? refreshToken;

  bool get isPending => jellyfinBody == null;
}

class OxplayerLoginAttemptException implements Exception {
  OxplayerLoginAttemptException(this.message);
  final String message;

  @override
  String toString() => message;
}
