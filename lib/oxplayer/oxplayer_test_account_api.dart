import 'dart:convert';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_auth_http.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/auth_provider.dart';

class OxplayerTestAccountApi {
  OxplayerTestAccountApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Response<AccountModel>?> signIn({
    required WidgetRef ref,
    required String deviceId,
  }) async {
    final response = await OxplayerAuthHttp.send(() => _client.post(
          OxplayerAuthHttp.uri('/auth/test-account'),
          headers: OxplayerAuthHttp.headers(
            extra: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          ),
          body: jsonEncode({'deviceId': deviceId}),
        ));

    if (response.statusCode != 200) {
      throw OxplayerTestAccountException(_errorMessage(response));
    }

    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final jellyfin = map['jellyfin'];
    if (jellyfin is! Map<String, dynamic>) {
      throw OxplayerTestAccountException('Invalid test account response');
    }

    final auth = AuthenticationResult.fromJson(jellyfin);
    final refresh = response.headers['x-ox-refresh-token'] ?? map['refreshToken']?.toString();
    final headers = <String, String>{};
    if (refresh != null && refresh.isNotEmpty) {
      headers['x-ox-refresh-token'] = refresh;
    }
    final raw = http.Response('', 200, headers: headers);
    final authResponse = Response<AuthenticationResult>(raw, auth);
    final accountResponse =
        await ref.read(authProvider.notifier).finishAuthenticationFromResult(authResponse);
    final account = accountResponse?.body;
    if (accountResponse != null && account != null) {
      await oxplayerPersistRefreshFromResponse(ref, account, accountResponse);
    }
    return accountResponse;
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Test sign-in failed (${response.statusCode})';
  }
}

class OxplayerTestAccountException implements Exception {
  OxplayerTestAccountException(this.message);
  final String message;

  @override
  String toString() => message;
}
