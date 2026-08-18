import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/login_screen_model.dart';
import 'package:fladder/oxplayer/oxplayer_account_switch.dart';
import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_main_bot_login_panel.dart';
import 'package:fladder/oxplayer/oxplayer_pending_route.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_connecting_experience.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_login_panel.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_qr_login_panel.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/screens/login/login_screen_credentials.dart';
import 'package:fladder/oxplayer/oxplayer_login_edit_user.dart';
import 'package:fladder/screens/login/login_user_grid.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/oxplayer/oxplayer_login_logo.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/fladder_config.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';

@RoutePage()
class OxplayerLoginScreen extends ConsumerStatefulWidget {
  const OxplayerLoginScreen({super.key});

  @override
  ConsumerState<OxplayerLoginScreen> createState() => _OxplayerLoginScreenState();
}

class _OxplayerLoginScreenState extends ConsumerState<OxplayerLoginScreen> {
  bool _bootstrapping = true;
  String? _bootstrapError;
  /// True only when [_bootstrapError] came from the TDLib bridge itself (stuck initializing,
  /// landed in a failed auth state, etc) — gates showing the explicit "log out" escape hatch,
  /// since resetting Telegram auth does nothing for unrelated bootstrap failures (missing server
  /// config, network errors, etc).
  bool _bootstrapErrorIsStuckSession = false;
  bool _editUsersMode = false;
  /// TV only: false = QR-first, true = phone panel after remote select.
  bool _tvUsePhone = false;
  /// false = TDLib (personal Telegram account), true = @main-bot (no account access at all).
  bool _useMainBot = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
      _bootstrapErrorIsStuckSession = false;
    });

    await OxplayerDotenv.ensureLoaded();
    final media = OxplayerEnv.effectiveMediaServerUrl;
    if (media == null) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _bootstrapError = context.localized.oxplayerLoginBootstrapEnvError;
      });
      return;
    }

    FladderConfig.baseUrl = media;

    try {
      await ref.read(authProvider.notifier).initModel();
    } catch (e) {
      if (mounted) {
        setState(() {
          _bootstrapping = false;
          _bootstrapError = '$e';
        });
      }
      return;
    }

    if (!mounted) return;
    oxplayerFlushBufferedPendingPath(ref);
    final err = ref.read(authProvider).errorMessage;
    if (err != null) {
      setState(() {
        _bootstrapping = false;
        _bootstrapError = err;
      });
      return;
    }

    // Warm TDLib during the same splash — do not show login UI until past setTdlibParameters.
    try {
      final phoneFirst = !_isTv(context);
      final controller = OxplayerTdlibBridgeController.instance();
      await controller.prepareForLoginScreen(
        phoneFirst: phoneFirst,
      );
      // TV defaults to QR; kick off token while splash still covers the screen. Only from a
      // state requestQrLogin() actually accepts — prepareForLoginScreen deliberately leaves an
      // already-`ready` session alone (see its doc), and calling requestQrLogin() on that throws
      // "Cannot start QR login from state=ready", which this catch below then misreports as a
      // stuck-session error. Confirmed live (2026-08-18): a cached bot-token session landing on
      // `ready` here hit exactly that. The panel that mounts next already handles `ready` itself
      // (re-checks current state in its own initState), so skipping here is enough.
      final kind = controller.state.kind;
      final canStartQr = kind == OxTdlibAuthStateKind.waitingForPhoneNumber ||
          kind == OxTdlibAuthStateKind.waitingForQrConfirmation;
      if (!phoneFirst && canStartQr) {
        await controller.requestQrLogin();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _bootstrapError = '$e';
        _bootstrapErrorIsStuckSession = e is OxplayerTdlibBridgeException;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _bootstrapping = false);
  }

  /// Retry action for a TDLib-originated error: restarts the whole app process when available
  /// (see OxplayerTdlibBridgeController.restartApp's doc — a plain in-process retry can end up
  /// doing nothing for a native client stuck in a `failed` auth state), falling back to a normal
  /// in-place [_bootstrap] retry on platforms without a restart implementation.
  Future<void> _retryTdlibError() async {
    final controller = OxplayerTdlibBridgeController.instance();
    if (!controller.canRestartApp) {
      await _bootstrap();
      return;
    }
    try {
      await controller.restartApp();
    } catch (_) {
      if (!mounted) return;
      await _bootstrap();
    }
  }

  Future<void> _confirmForceLogoutStuckSession() async {
    final loc = context.localized;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.oxplayerStuckSessionLogoutTitle),
        content: Text(loc.oxplayerStuckSessionLogoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(loc.logout),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await OxplayerTdlibBridgeController.instance().resetStuckSession();
    if (!mounted) return;
    await _bootstrap();
  }

  Future<void> _onLoginSuccess() async {
    await loggedInGoToHome(context, ref);
  }

  /// Hidden Play review path: hold logo 5s → demo library. No on-screen hint.
  Widget _loginLogo({bool holdEnabled = true}) {
    final logo = const OxplayerLoginLogo();
    if (!holdEnabled) return logo;
    return OxplayerTestAccountQrHold(
      onHoldComplete: () {
        unawaited(oxplayerSignInAsTestAccount(
          ref: ref,
          context: context,
          onSuccess: _onLoginSuccess,
        ));
      },
      child: logo,
    );
  }

  bool _isTv(BuildContext context) {
    final leanBack = ref.read(argumentsStateProvider).leanBackMode;
    return leanBack || AdaptiveLayout.viewSizeOf(context) == ViewSize.television;
  }

  void _openUserEditDialogue(AccountModel user) {
    showDialog(
      context: context,
      builder: (context) => OxplayerLoginEditUser(user: user),
    );
  }

  void _backToAccountGrid() {
    setState(() {
      _editUsersMode = false;
    });
    ref.read(authProvider.notifier).goUserSelect();
  }

  bool _consumeSystemBack(List<AccountModel> accounts, bool showAccountGrid) {
    if (accounts.isEmpty) return false;

    if (!showAccountGrid) {
      _backToAccountGrid();
      return true;
    }

    return false;
  }

  void _startAddAccount() {
    setState(() {
      _editUsersMode = false;
    });
    ref.read(authProvider.notifier).addNewUser();
  }

  @override
  Widget build(BuildContext context) {
    final screen = ref.watch(authProvider.select((value) => value.screen));
    final accounts = ref.watch(authProvider.select((value) => value.accounts));
    final showAccountGrid = screen == LoginScreenType.users && accounts.isNotEmpty;
    final showBackToAccounts = !showAccountGrid && accounts.isNotEmpty;
    final interceptSystemBack = accounts.isNotEmpty && !showAccountGrid;

    return PopScope(
      canPop: !interceptSystemBack,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _consumeSystemBack(accounts, showAccountGrid);
      },
      child: Scaffold(
      floatingActionButton: showAccountGrid
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 16,
              children: [
                AdaptiveFab(
                  context: context,
                  key: const Key('ox_new_user_button'),
                  heroTag: 'ox_new_user_button',
                  child: const Icon(IconsaxPlusLinear.add_square),
                  onPressed: _startAddAccount,
                ).normal,
                AdaptiveFab(
                  context: context,
                  key: const Key('ox_edit_user_button'),
                  heroTag: 'ox_edit_user_button',
                  backgroundColor:
                      _editUsersMode ? Theme.of(context).colorScheme.errorContainer : null,
                  child: const Icon(IconsaxPlusLinear.edit_2),
                  onPressed: () => setState(() => _editUsersMode = !_editUsersMode),
                ).normal,
              ],
            )
          : showBackToAccounts
              ? ValueListenableBuilder<bool>(
                  valueListenable: OxplayerTdlibConnectingExperience.isActive,
                  builder: (context, connecting, _) => connecting
                      ? const SizedBox.shrink()
                      : FloatingActionButton(
                          tooltip: context.localized.switchUser,
                          onPressed: _backToAccountGrid,
                          child: const Icon(IconsaxPlusLinear.arrow_left_2),
                        ),
                )
              : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: showAccountGrid ? 1000 : 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _bootstrapping
                    // This is where prepareForLoginScreen()/requestQrLogin() actually run (see
                    // _bootstrap) — the same 15-20s TDLib connect the panels' own connecting
                    // state covers, just earlier. Without this, that whole stretch showed a bare
                    // spinner and the panels' animated version rarely got a chance to appear at
                    // all, because _bootstrapping only clears after this work already finished.
                    ? const OxplayerTdlibConnectingExperience()
                    : _bootstrapError != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _loginLogo(holdEnabled: false),
                              const SizedBox(height: 16),
                              Text(
                                _bootstrapError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).colorScheme.error),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _bootstrapErrorIsStuckSession ? _retryTdlibError : _bootstrap,
                                child: Text(context.localized.retry),
                              ),
                              if (_bootstrapErrorIsStuckSession) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _confirmForceLogoutStuckSession,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.error,
                                  ),
                                  child: Text(context.localized.logout),
                                ),
                              ],
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _loginLogo(),
                              const SizedBox(height: 24),
                              AnimatedFadeSize(
                                child: showAccountGrid
                                    ? LoginUserGrid(
                                        users: accounts,
                                        editMode: _editUsersMode,
                                        onPressed: (user) => oxplayerTapSavedAccount(context, ref, user),
                                        onLongPress: _openUserEditDialogue,
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          if (showBackToAccounts)
                                            ValueListenableBuilder<bool>(
                                              valueListenable:
                                                  OxplayerTdlibConnectingExperience.isActive,
                                              builder: (context, connecting, _) => connecting
                                                  ? const SizedBox.shrink()
                                                  : Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        Align(
                                                          alignment: Alignment.centerLeft,
                                                          child: TextButton.icon(
                                                            onPressed: _backToAccountGrid,
                                                            icon: const Icon(
                                                                IconsaxPlusLinear.arrow_left_2),
                                                            label: Text(context.localized.switchUser),
                                                          ),
                                                        ),
                                                        const SizedBox(height: 8),
                                                      ],
                                                    ),
                                            ),
                                          _useMainBot
                                              ? OxplayerMainBotLoginPanel(
                                                  onSuccess: _onLoginSuccess,
                                                  onBack: () => setState(() => _useMainBot = false),
                                                )
                                              : _isTv(context)
                                                  ? (_tvUsePhone
                                                      ? OxplayerTdlibLoginPanel(
                                                          onSuccess: _onLoginSuccess,
                                                          showQrShortcut: false,
                                                          onBackToQr: () async {
                                                            final tdlib =
                                                                OxplayerTdlibBridgeController.instance();
                                                            await tdlib.resetForPhoneLogin();
                                                            await tdlib.requestQrLogin();
                                                            if (mounted) {
                                                              setState(() => _tvUsePhone = false);
                                                            }
                                                          },
                                                        )
                                                      : OxplayerTdlibQrLoginPanel(
                                                          onSuccess: _onLoginSuccess,
                                                          onUsePhoneNumber: () async {
                                                            await OxplayerTdlibBridgeController
                                                                .instance()
                                                                .resetForPhoneLogin();
                                                            if (mounted) {
                                                              setState(() => _tvUsePhone = true);
                                                            }
                                                          },
                                                          onNeedTwoFactorPassword: () {
                                                            // Keep TDLib waitingForPassword — do not reset.
                                                            setState(() => _tvUsePhone = true);
                                                          },
                                                        ))
                                                  : OxplayerTdlibLoginPanel(
                                                      onSuccess: _onLoginSuccess,
                                                    ),
                                          if (!_useMainBot)
                                            ListenableBuilder(
                                              listenable: OxplayerTdlibBridgeController.instance(),
                                              builder: (context, _) {
                                                final kind = OxplayerTdlibBridgeController.instance().state.kind;
                                                final onFirstSessionStep = kind ==
                                                        OxTdlibAuthStateKind.waitingForPhoneNumber ||
                                                    kind == OxTdlibAuthStateKind.waitingForQrConfirmation ||
                                                    kind == OxTdlibAuthStateKind.uninitialized;
                                                if (!onFirstSessionStep) {
                                                  return const SizedBox.shrink();
                                                }
                                                return Padding(
                                                  padding: const EdgeInsets.only(top: 14),
                                                  child: TextButton(
                                                    onPressed: () => setState(() => _useMainBot = true),
                                                    child: Text(
                                                      "Don't want to link your Telegram account? Sign in with @${OxplayerEnv.botUsername ?? 'main-bot'} instead",
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
