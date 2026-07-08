import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_route_env.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_image_auth.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';
import 'package:fladder/oxplayer/oxplayer_session_store.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/oxplayer/oxplayer_session_auth_prompt.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kOxJellyfinRefreshUsername = '__ox_refresh__';

/// Cold-start session check must not block the splash screen indefinitely.
const kOxSessionRestoreTimeout = Duration(seconds: 12);

/// Legacy hook for session revocation; prefer [oxplayerPromptReLogin].
final oxplayerSessionRevokedProvider = StateProvider<int>((ref) => 0);

OxplayerSessionStore _sessionStore(OxplayerRead read) => OxplayerSessionStore(read(sharedPreferencesProvider));

Future<void> oxplayerPersistRefreshFromResponse(
  WidgetRef ref,
  AccountModel account,
  Response<dynamic> response,
) async {
  final refresh = _readRefreshHeader(response);
  if (refresh == null) return;
  await _sessionStore(ref.read).save(account, refresh);
}

String? _readRefreshHeader(Response<dynamic> response) {
  final headers = response.base.headers;
  return headers['x-ox-refresh-token'] ?? headers['X-Ox-Refresh-Token'];
}

/// Validates the stored access token on cold start; refreshes or clears the session.
Future<bool> oxplayerRestoreSession(WidgetRef ref, AccountModel account) async {
  final ok = await _restoreSession(ref.read, account);
  if (ok && OxplayerEnv.isEnabled) {
    await oxplayerConfigureSeerrFromServer(ref);
  }
  return ok;
}

Future<bool> _restoreSession(OxplayerRead read, AccountModel incoming) async {
  var account = incoming;
  read(userProvider.notifier).updateUser(account);
  OxplayerImageAuth.syncFromAccount(account);

  if (account.credentials.url.trim().isEmpty) {
    final fallback = OxplayerEnv.apiBaseUrl;
    if (fallback == null || fallback.isEmpty) {
      return false;
    }
    account = account.copyWith(
      credentials: account.credentials.copyWith(url: fallback),
    );
    read(userProvider.notifier).updateUser(account);
  } else {
    final migrated = OxplayerRouteEnv.rewriteLegacyIranUrl(account.credentials.url);
    if (migrated != account.credentials.url) {
      account = account.copyWith(
        credentials: account.credentials.copyWith(url: migrated),
      );
      read(userProvider.notifier).updateUser(account);
      await read(sharedUtilityProvider).updateAccountInfo(account);
    }
  }

  try {
    final api = read(jellyApiProvider);
    final me = await api.usersMeGet().timeout(kOxSessionRestoreTimeout);
    if (me.isSuccessful) return true;

    if (me.statusCode != 401) {
      // Offline or transient error — keep local session (Fladder behaviour).
      return true;
    }

    try {
      final refreshed = await oxplayerTryRefreshSession(read).timeout(kOxSessionRestoreTimeout);
      if (refreshed) return true;
      // Transient refresh failure (5xx) — keep cached credentials.
      if (read(userProvider) != null) return true;
      return false;
    } on TimeoutException {
      // API briefly down (deploy) — keep cached session; client retries on next request.
      return true;
    }
  } on TimeoutException {
    // Server unreachable — do not block splash; open app with cached credentials.
    return true;
  } on IOException {
    return true;
  }
}

/// Attempts to exchange the stored refresh token for a new access token.
Future<bool> oxplayerTryRefreshSession(OxplayerRead read) async {
  return _refreshGate.run(() => _refreshSession(read));
}

Future<void> oxplayerInvalidateLocalSession(OxplayerRead read, AccountModel account) async {
  await _sessionStore(read).clear(account);
  OxplayerImageAuth.clear();
  final cleared = account.copyWith(
    credentials: account.credentials.copyWith(token: ''),
  );
  await read(sharedUtilityProvider).updateAccountInfo(cleared);
  read(authProvider.notifier).clearAllProviders();
  read(oxplayerSessionRevokedProvider.notifier).state++;
}

/// Registers the app router for auth-error logout navigation.
void oxplayerAttachSessionRouter(WidgetRef ref, StackRouter router) {
  ref.read(oxplayerSessionRouterProvider.notifier).state = router;
}

final _RefreshGate _refreshGate = _RefreshGate();

class _RefreshGate {
  Future<bool>? _inFlight;

  Future<bool> run(Future<bool> Function() action) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = action().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }
}

Future<bool> _refreshSession(OxplayerRead read) async {
  final account = read(userProvider);
  if (account == null) return false;

  final refreshToken = await _sessionStore(read).read(account);
  if (refreshToken == null) {
    return false;
  }

  final credentials = account.credentials;
  if (credentials.url.isEmpty) {
    return false;
  }

  final client = createJellyfinApiForAccountUnauthenticated(
    credentials.url,
    oxplayerMediaBrowserHeaders(read, credentials),
  );

  final response = await client
      .usersAuthenticateByNamePost(
        body: AuthenticateUserByName(username: kOxJellyfinRefreshUsername, pw: refreshToken),
      )
      .timeout(kOxSessionRestoreTimeout);

  final accessOk = response.isSuccessful && (response.body?.accessToken?.isNotEmpty ?? false);

  if (!accessOk) {
    return false;
  }

  final access = response.body!.accessToken!;
  final updated = account.copyWith(
    credentials: credentials.copyWith(
      token: access,
      serverId: response.body?.serverId ?? credentials.serverId,
    ),
    lastUsed: DateTime.now(),
  );

  await read(sharedUtilityProvider).addAccount(updated);
  read(userProvider.notifier).updateUser(updated);
  OxplayerImageAuth.syncFromAccount(updated);

  final newRefresh = _readRefreshHeader(response);
  if (newRefresh != null) {
    await _sessionStore(read).save(updated, newRefresh);
  }

  return true;
}
