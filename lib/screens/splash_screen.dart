import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/oxplayer/oxplayer_session.dart';
import 'package:fladder/oxplayer/oxplayer_splash_telemetry.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
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
      await Future.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;

      _splashTiming.markAfterInitialDelay();

      final AccountModel? lastUsedAccount = ref.read(sharedUtilityProvider).getActiveAccount();
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
        context.router.replace(const DashboardRoute());
      } else {
        context.router.replace(const OxplayerLoginRoute());
      }
    } else {
      // AuthGuard [redirectUntil] completes via this callback only.
      widget.loggedIn?.call(loggedIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const NotificationManagerInitializer(
      child: Scaffold(
        body: Center(
          child: FractionallySizedBox(
            heightFactor: 0.4,
            child: FladderLogo(),
          ),
        ),
      ),
    );
  }
}
