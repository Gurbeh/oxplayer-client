import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OxplayerSplashAuthResult {
  /// No stored account or session tokens are invalid.
  needsLogin,

  /// Session restored; open the app shell.
  sessionReady,

  /// Session restored; show lock screen (biometric / PIN) before use.
  sessionWithLock,
}

/// OX cold-start: restore API session for any saved account, then decide lock vs home.
Future<OxplayerSplashAuthResult> oxplayerResolveSplashAuth(
  WidgetRef ref,
  AccountModel account,
) async {
  final sessionOk = await oxplayerRestoreSession(ref, account);
  if (!sessionOk) return OxplayerSplashAuthResult.needsLogin;

  if (account.askForAuthOnLaunch && account.authMethod.shouldLock) {
    return OxplayerSplashAuthResult.sessionWithLock;
  }
  return OxplayerSplashAuthResult.sessionReady;
}
