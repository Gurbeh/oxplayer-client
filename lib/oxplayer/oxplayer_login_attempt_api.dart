import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_auth_http.dart';

class OxplayerLoginAttemptCreated {
  const OxplayerLoginAttemptCreated({required this.attemptId, required this.expiresInSeconds});

  final String attemptId;
  final int expiresInSeconds;
}

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

class OxplayerLoginAttemptApi {
  OxplayerLoginAttemptApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) => OxplayerAuthHttp.uri(path, query);

  Map<String, String> _headers({Map<String, String>? extra}) =>
      OxplayerAuthHttp.headers(extra: extra);

  Future<OxplayerLoginAttemptCreated> createAttempt({required String deviceId}) async {
    final response = await OxplayerAuthHttp.send(() => _client.post(
          _uri('/auth/login-attempt'),
          headers: _headers(extra: {'Content-Type': 'application/json', 'Accept': 'application/json'}),
          body: jsonEncode({'deviceId': deviceId}),
        ));
    if (response.statusCode != 201) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final id = map['attemptId'] as String?;
    if (id == null || id.isEmpty) {
      throw OxplayerLoginAttemptException('Invalid login attempt response');
    }
    return OxplayerLoginAttemptCreated(
      attemptId: id,
      expiresInSeconds: (map['expiresIn'] as num?)?.toInt() ?? 600,
    );
  }

  /// Polls until the bot approves, the attempt expires, or [timeout] elapses.
  ///
  /// Uses short server long-poll windows so Android/iOS can background the app
  /// (e.g. switch to Telegram) without killing one 55s HTTP connection.
  Future<OxplayerLoginAttemptPollResult> pollUntilComplete({
    required String attemptId,
    required String deviceId,
    int waitSeconds = 12,
    Duration timeout = const Duration(minutes: 10),
    bool Function()? shouldContinue,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var transientFailures = 0;

    while (DateTime.now().isBefore(deadline)) {
      if (shouldContinue != null && !shouldContinue()) {
        throw OxplayerLoginAttemptException('Sign-in cancelled');
      }
      try {
        final result = await _pollOnce(
          attemptId: attemptId,
          deviceId: deviceId,
          waitSeconds: waitSeconds,
        );
        transientFailures = 0;
        if (!result.isPending) {
          return result;
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } on OxplayerLoginAttemptException {
        rethrow;
      } catch (e) {
        if (!_isTransientNetworkError(e)) {
          throw OxplayerLoginAttemptException(e.toString());
        }
        transientFailures++;
        if (transientFailures > 200) {
          throw OxplayerLoginAttemptException(
            'Connection lost while waiting. Return to the app and tap Sign in with Telegram again.',
          );
        }
        // Typical when the app is backgrounded for Telegram — retry when user returns.
        await Future<void>.delayed(
          Duration(milliseconds: 600 + (transientFailures % 6) * 250),
        );
      }
    }
    throw OxplayerLoginAttemptException('Timed out waiting for Telegram approval.');
  }

  Future<OxplayerLoginAttemptPollResult> _pollOnce({
    required String attemptId,
    required String deviceId,
    required int waitSeconds,
  }) async {
    final uri = _uri('/auth/login-attempt/$attemptId', {
      'deviceId': deviceId,
      'wait': '$waitSeconds',
    });
    final response = await OxplayerAuthHttp.send(() => _client
        .get(
          uri,
          headers: _headers(extra: {'Accept': 'application/json'}),
        )
        .timeout(Duration(seconds: waitSeconds + 20)));

    if (response.statusCode == 200) {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      if (map.containsKey('AccessToken') || map.containsKey('accessToken')) {
        final refresh = response.headers['x-ox-refresh-token'];
        return OxplayerLoginAttemptPollResult.completed(map, refreshToken: refresh);
      }
      if (map['status'] == 'pending') {
        return const OxplayerLoginAttemptPollResult.pending();
      }
      final nested = map['jellyfin'];
      if (nested is Map<String, dynamic>) {
        final refresh = response.headers['x-ox-refresh-token'];
        return OxplayerLoginAttemptPollResult.completed(nested, refreshToken: refresh);
      }
      throw OxplayerLoginAttemptException('Unexpected poll response');
    }
    if (response.statusCode == 409) {
      return const OxplayerLoginAttemptPollResult.pending();
    }
    if (response.statusCode == 410 || response.statusCode == 404) {
      throw OxplayerLoginAttemptException(_errorMessage(response));
    }
    throw OxplayerLoginAttemptException(_errorMessage(response));
  }

  static bool _isTransientNetworkError(Object e) {
    return e is http.ClientException ||
        e is SocketException ||
        e is TimeoutException ||
        e is HandshakeException;
  }

  String _errorMessage(http.Response response) {
    try {
      final map = jsonDecode(response.body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.isNotEmpty) return err;
    } catch (_) {}
    return 'Login failed (${response.statusCode})';
  }
}

class OxplayerLoginAttemptException implements Exception {
  OxplayerLoginAttemptException(this.message);
  final String message;

  @override
  String toString() => message;
}
