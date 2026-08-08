/// Shared response types for Telegram-identity login exchanges.
///
/// The original bot-deep-link/code-approval flow (`OxplayerLoginAttemptApi.createAttempt`/
/// `pollUntilComplete`, backed by the now-removed `/auth/login-attempt` route) has been replaced by
/// TDLib sign-in (see `oxplayer_tdlib_bridge_controller.dart`). These two types are still shared by
/// that flow and by `oxplayer_telegram_webapp_auth_api.dart` since both paths return the same
/// AuthenticationResult/`X-Ox-Refresh-Token` shape — see `oxplayer_jellyfin_auth.dart`.
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
