import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/login/lock_screen.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/shared/passcode_input.dart';
import 'package:fladder/util/auth_service.dart';
import 'package:fladder/util/localization_helper.dart';

/// Switch to a saved OX account: restore session, Seerr config, then home or lock.
Future<bool> oxplayerSwitchToAccount(
  BuildContext context,
  WidgetRef ref,
  AccountModel account,
) async {
  await ref.read(authProvider.notifier).switchUser();

  final updated = account.copyWith(lastUsed: DateTime.now());
  await ref.read(sharedUtilityProvider).updateAccountInfo(updated);
  ref.read(userProvider.notifier).updateUser(updated);

  final sessionOk = await oxplayerRestoreSession(ref, updated);
  if (!sessionOk) {
    if (context.mounted) {
      FladderSnack.show(context.localized.somethingWentWrong, context: context);
      ref.read(authProvider.notifier).goUserSelect();
    }
    return false;
  }

  ref.read(lockScreenActiveProvider.notifier).update((state) => false);

  if (!context.mounted) return true;

  if (updated.askForAuthOnLaunch && updated.authMethod.shouldLock) {
    await context.router.replaceAll([const DashboardRoute()]);
    if (context.mounted) {
      await context.router.push(const LockRoute());
    }
    return true;
  }

  await loggedInGoToHome(context, ref);
  return true;
}

/// Account-grid tap handler with per-profile lock (biometrics / PIN).
Future<void> oxplayerTapSavedAccount(
  BuildContext context,
  WidgetRef ref,
  AccountModel user,
) async {
  Future<void> switchFn() => oxplayerSwitchToAccount(context, ref, user);

  switch (user.authMethod) {
    case Authentication.autoLogin:
    case Authentication.none:
      await switchFn();
    case Authentication.biometrics:
      final authenticated = await AuthService.authenticateUser(context, user);
      if (authenticated && context.mounted) {
        await switchFn();
      }
    case Authentication.passcode:
      if (!context.mounted) return;
      showPassCodeDialog(context, (newPin) async {
        if (newPin == user.localPin) {
          await switchFn();
        } else if (context.mounted) {
          FladderSnack.show(context.localized.incorrectPinTryAgain, context: context);
        }
      });
  }
}
