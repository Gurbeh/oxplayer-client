import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_pending_route.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/oxplayer/oxplayer_splash_auth.dart';
import 'package:fladder/oxplayer/oxplayer_splash_telemetry.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/oxplayer/ox_splash_brand.dart';
import 'package:fladder/screens/shared/fladder_logo.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';

@RoutePage()
class SplashScreen extends ConsumerStatefulWidget {
  final Function(bool loggedIn)? loggedIn;
  const SplashScreen({this.loggedIn, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  final _splashTiming = OxplayerSplashTiming();

  @override
  void initState() {
    super.initState();
    _splashTiming.markStarted();
    WidgetsBinding.instance.addPostFrameCallback((value) async {
      _splashTiming.markFirstFrame();
      if (OxplayerConfig.isEnabled && mounted) {
        await precacheImage(
          ResizeImage.resizeIfNeeded(512, null, const AssetImage(OxSplashBrand.assetPath)),
          context,
        );
      }
      await Future.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;

      _splashTiming.markAfterInitialDelay();

      final AccountModel? lastUsedAccount = OxplayerConfig.isEnabled
          ? ref.read(sharedUtilityProvider).getMostRecentAccount()
          : ref.read(sharedUtilityProvider).getActiveAccount();
      ref.read(userProvider.notifier).updateUser(lastUsedAccount);

      if (!context.mounted) return;

      final newWindow = ref.read(argumentsStateProvider).newWindow == true;
      _splashTiming.markAccountContext(
        hadAccount: lastUsedAccount != null,
        newWindow: newWindow,
        authMethod: _splashAuthMethodLabel(lastUsedAccount?.authMethod),
      );

      if (lastUsedAccount == null || newWindow) {
        callBackOrNavigate(false);
        return;
      }

      if (OxplayerConfig.isEnabled) {
        _splashTiming.markSessionRestoreStarted();
        final result = await oxplayerResolveSplashAuth(ref, lastUsedAccount);
        _splashTiming.markSessionRestoreEnded(result != OxplayerSplashAuthResult.needsLogin);
        if (!context.mounted) return;
        switch (result) {
          case OxplayerSplashAuthResult.needsLogin:
            callBackOrNavigate(false);
          case OxplayerSplashAuthResult.sessionReady:
            callBackOrNavigate(true);
          case OxplayerSplashAuthResult.sessionWithLock:
            navigateWithLockOnLaunch();
        }
        return;
      }

      switch (lastUsedAccount.authMethod) {
        case Authentication.autoLogin:
          var sessionOk = false;
          _splashTiming.markSessionRestoreStarted();
          try {
            sessionOk = await oxplayerRestoreSession(ref, lastUsedAccount);
          } catch (_) {
            sessionOk = false;
          }
          _splashTiming.markSessionRestoreEnded(sessionOk);
          if (context.mounted) callBackOrNavigate(sessionOk);
          break;
        case Authentication.biometrics:
        case Authentication.none:
        case Authentication.passcode:
          callBackOrNavigate(false);
          break;
      }
    });
  }

  static String? _splashAuthMethodLabel(Authentication? method) {
    return switch (method) {
      Authentication.autoLogin => 'autoLogin',
      Authentication.biometrics => 'biometrics',
      Authentication.passcode => 'passcode',
      Authentication.none => 'none',
      null => null,
    };
  }

  void callBackOrNavigate(bool loggedIn) {
    final destination = widget.loggedIn != null
        ? 'auth_guard_callback'
        : (loggedIn ? 'dashboard' : 'login');
    unawaited(_splashTiming.finishAndReport(destination: destination, loggedIn: loggedIn));

    if (widget.loggedIn == null) {
      if (loggedIn) {
        if (OxplayerConfig.isEnabled) {
          oxplayerFlushBufferedPendingPath(ref);
          unawaited(oxplayerNavigateAfterLogin(context, ref));
        } else {
          context.router.replace(const DashboardRoute());
        }
      } else {
        oxplayerFlushBufferedPendingPath(ref);
        if (OxplayerConfig.isEnabled) {
          context.router.replace(const OxplayerLoginRoute());
          ref.read(authProvider.notifier).initModel();
        } else {
          context.router.replace(LoginRoute());
        }
      }
    } else {
      // AuthGuard [redirectUntil] completes via this callback only.
      widget.loggedIn?.call(loggedIn);
    }
  }

  void navigateWithLockOnLaunch() {
    final destination = widget.loggedIn != null ? 'auth_guard_callback_with_lock' : 'dashboard_with_lock';
    unawaited(_splashTiming.finishAndReport(destination: destination, loggedIn: true));

    void pushLock() {
      if (!context.mounted) return;
      context.router.push(const LockRoute());
    }

    if (widget.loggedIn == null) {
      if (OxplayerConfig.isEnabled) {
        oxplayerFlushBufferedPendingPath(ref);
        unawaited(oxplayerNavigateAfterLogin(context, ref));
        WidgetsBinding.instance.addPostFrameCallback((_) => pushLock());
      } else {
        context.router.replace(const DashboardRoute());
        WidgetsBinding.instance.addPostFrameCallback((_) => pushLock());
      }
    } else {
      widget.loggedIn?.call(true);
      WidgetsBinding.instance.addPostFrameCallback((_) => pushLock());
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationManagerInitializer(
      child: Scaffold(
        body: Center(
          child: FractionallySizedBox(
            heightFactor: 0.4,
            child: OxplayerConfig.isEnabled ? const OxSplashBrand() : const FladderLogo(),
          ),
        ),
      ),
    );
  }
}
