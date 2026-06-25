import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_image_auth.dart';
import 'package:fladder/oxplayer/oxplayer_seerr_auto_config.dart';
import 'package:fladder/oxplayer/oxplayer_session_store.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/oxplayer/oxplayer_navigation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kOxJellyfinRefreshUsername = '__ox_refresh__';

/// Cold-start session check must not block the splash screen indefinitely.
const kOxSessionRestoreTimeout = Duration(seconds: 12);

/// Bumped when the server rejects the session and local credentials are cleared.
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

Future<bool> _restoreSession(OxplayerRead read, AccountModel account) async {
  read(userProvider.notifier).updateUser(account);
  OxplayerImageAuth.syncFromAccount(account);

  if (account.credentials.url.trim().isEmpty) {
    return false;
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

/// Listen for server-driven session invalidation. Call from [State.initState] only
/// with [ref.listenManual] (not [ref.listen], which requires an active build).
ProviderSubscription<int> oxplayerAttachSessionRevokedListener(WidgetRef ref, StackRouter router) {
  return ref.listenManual<int>(oxplayerSessionRevokedProvider, (previous, next) {
    if (next == 0 || next == previous) return;
    router.replaceAll(oxplayerSignOutRouteList(ref));
    ref.read(authProvider.notifier).initModel();
  });
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
    await oxplayerInvalidateLocalSession(read, account);
    return false;
  }

  final credentials = account.credentials;
  if (credentials.url.isEmpty) {
    await oxplayerInvalidateLocalSession(read, account);
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

  final statusCode = response.statusCode;
  final accessOk = response.isSuccessful && (response.body?.accessToken?.isNotEmpty ?? false);

  if (!accessOk) {
    if (statusCode == 401 || statusCode == 403) {
      await oxplayerInvalidateLocalSession(read, account);
    }
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
