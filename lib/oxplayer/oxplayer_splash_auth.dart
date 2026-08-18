import 'dart:io';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum OxplayerSplashAuthResult {
  /// No stored account or session tokens are invalid.
  needsLogin,

  /// Session restored; open the app shell.
  sessionReady,

  /// Session restored; show lock screen (biometric / PIN) before use.
  sessionWithLock,
}

bool _oxTdlibSessionGateSupported() {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isWindows;
  } catch (_) {
    return false;
  }
}

/// OX cold-start: restore API session for any saved account, then decide lock vs home.
///
/// When this build has TDLib credentials, also require a **ready** Telegram user-session
/// on device. Legacy OX logins (bot deep-link) without MTProto are signed out so the user
/// re-authenticates via Telegram. Users who already completed Telegram sign-in stay signed in.
Future<OxplayerSplashAuthResult> oxplayerResolveSplashAuth(
  WidgetRef ref,
  AccountModel account,
) async {
  try {
    final sessionOk = await oxplayerRestoreSession(ref, account);
    if (!sessionOk) {
      await oxplayerLogoutLocallySkippingServer(ref.read, fallbackAccount: account);
      return OxplayerSplashAuthResult.needsLogin;
    }

    if (OxplayerEnv.telegramDirectPlayConfigured && _oxTdlibSessionGateSupported()) {
      final hasTelegramSession =
          await OxplayerTdlibBridgeController.instance().hasReadyUserSession();
      if (!hasTelegramSession) {
        // Keep OX tokens. `adb install -r` / TV Keystore often leaves TDLib in
        // WAITING_FOR_QR; wiping here forced QR login after every rebuild.
        debugPrint('OX_IMAGE phase=splash_tdlib_not_ready keep_ox_session=true');
        return OxplayerSplashAuthResult.sessionReady;
      }
    }

    if (account.askForAuthOnLaunch && account.authMethod.shouldLock) {
      return OxplayerSplashAuthResult.sessionWithLock;
    }
    return OxplayerSplashAuthResult.sessionReady;
  } catch (_) {
    try {
      await oxplayerLogoutLocallySkippingServer(ref.read, fallbackAccount: account);
    } catch (_) {}
    return OxplayerSplashAuthResult.needsLogin;
  }
}
