import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:chopper/chopper.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
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

/// Stored account URLs from before the kabazhe.ir → oxplayer.ir domain rename.
String _rewriteLegacyDomain(String raw) {
  return raw
      .replaceAll('api.kabazhe.ir', 'api.oxplayer.ir')
      .replaceAll('www.kabazhe.ir', 'www.oxplayer.ir')
      .replaceAll('kabazhe.ir', 'oxplayer.ir');
}

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
    await OxplayerOxLoginKindStore.promoteToCurrent(account.id);
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
    final migrated = _rewriteLegacyDomain(account.credentials.url);
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
      final outcome = await _refreshGate.run(() => _refreshSession(read)).timeout(kOxSessionRestoreTimeout);
      if (outcome == _RefreshOutcome.ok) return true;
      if (outcome == _RefreshOutcome.transient) {
        // 5xx / empty body — keep cached credentials (Fladder offline behaviour).
        return true;
      }
      // 401/403 or no refresh token: stale upgrade session. Drop it so splash can reach login.
      await oxplayerInvalidateLocalSession(read, account);
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
  final outcome = await _refreshGate.run(() => _refreshSession(read));
  return outcome == _RefreshOutcome.ok;
}

/// Clears tokens and the saved account without waiting on Jellyfin/Seerr/Telegram.
/// Splash uses this when a stored login is no longer valid — [authProvider.logOutUser]
/// awaits `Sessions/Logout` with no timeout and will freeze the splash if the API is down.
Future<void> oxplayerLogoutLocallySkippingServer(
  OxplayerRead read, {
  AccountModel? fallbackAccount,
}) async {
  final account = read(userProvider) ?? fallbackAccount;
  if (account != null) {
    await _sessionStore(read).clear(account);
    final saved = List<AccountModel>.from(read(sharedUtilityProvider).getAccounts())
      ..removeWhere((element) => element.sameIdentity(account));
    await read(sharedUtilityProvider).saveAccounts(saved);
  }
  OxplayerImageAuth.clear();
  read(authProvider.notifier).clearAllProviders();
  read(oxplayerSessionRevokedProvider.notifier).state++;
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

enum _RefreshOutcome { ok, invalid, transient }

final _RefreshGate _refreshGate = _RefreshGate();

class _RefreshGate {
  Future<_RefreshOutcome>? _inFlight;

  Future<_RefreshOutcome> run(Future<_RefreshOutcome> Function() action) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = action().whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }
}

Future<_RefreshOutcome> _refreshSession(OxplayerRead read) async {
  final account = read(userProvider);
  if (account == null) return _RefreshOutcome.invalid;

  final refreshToken = await _sessionStore(read).read(account);
  if (refreshToken == null) {
    return _RefreshOutcome.invalid;
  }

  final credentials = account.credentials;
  if (credentials.url.isEmpty) {
    return _RefreshOutcome.invalid;
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
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _RefreshOutcome.invalid;
    }
    return _RefreshOutcome.transient;
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

  return _RefreshOutcome.ok;
}
