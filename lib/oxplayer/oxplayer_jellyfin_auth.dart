import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Applies a successful `/auth/telegram` (or test-account) response to [authProvider].
///
/// [OxplayerLoginAttemptPollResult] is the shared response wrapper — not a bot login-attempt poll.
Future<Response<AccountModel>?> oxplayerAuthenticateFromLoginAttemptPoll(
  WidgetRef ref,
  OxplayerLoginAttemptPollResult poll,
) async {
  final body = poll.jellyfinBody;
  if (body == null) return null;
  final auth = AuthenticationResult.fromJson(body);
  final raw = http.Response('', 200, headers: {
    if (poll.refreshToken != null) 'x-ox-refresh-token': poll.refreshToken!,
  });
  final response = Response<AuthenticationResult>(raw, auth);
  final accountResponse =
      await ref.read(authProvider.notifier).finishAuthenticationFromResult(response);
  final account = accountResponse?.body;
  if (accountResponse != null && account != null) {
    await oxplayerPersistRefreshFromResponse(ref, account, accountResponse);
  }
  return accountResponse;
}
