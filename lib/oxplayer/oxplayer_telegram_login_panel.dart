import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as urilauncher;

import 'package:fladder/oxplayer/oxplayer_bot_qr_dialog.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/clipboard_helper.dart';
import 'package:fladder/util/localization_helper.dart';

class OxplayerTelegramLoginPanel extends ConsumerStatefulWidget {
  const OxplayerTelegramLoginPanel({
    required this.onSuccess,
    super.key,
  });

  final Future<void> Function() onSuccess;

  @override
  ConsumerState<OxplayerTelegramLoginPanel> createState() => _OxplayerTelegramLoginPanelState();
}

class _OxplayerTelegramLoginPanelState extends ConsumerState<OxplayerTelegramLoginPanel> with WidgetsBindingObserver {
  final _api = OxplayerLoginAttemptApi();
  String? _attemptId;
  String? _loginCode;
  String? _telegramLink;
  bool _waiting = false;
  bool _cancelPoll = false;
  bool _pollRunning = false;
  bool _testSignInInProgress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAttempt());
  }

  @override
  void dispose() {
    _cancelPoll = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_attemptId != null && !_pollRunning && !_testSignInInProgress) {
        unawaited(_pollForCompletion(userOpenedTelegram: _waiting));
      }
      setState(() {});
    }
  }

  String? _deviceId() {
    final creds = ref.read(authProvider).serverLoginModel?.tempCredentials;
    return creds?.deviceId;
  }

  Future<void> _startAttempt() async {
    final l10n = context.localized;
    final deviceId = _deviceId();
    if (deviceId == null || deviceId.isEmpty) {
      setState(() => _error = l10n.oxplayerLoginDeviceNotReady);
      return;
    }
    _cancelPoll = true;
    for (var i = 0; i < 100 && _pollRunning; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _cancelPoll = false;
    setState(() {
      _error = null;
      _waiting = false;
      _attemptId = null;
      _loginCode = null;
      _telegramLink = null;
    });
    try {
      final created = await _api.createAttempt(deviceId: deviceId);
      if (!mounted) return;
      final link = OxplayerEnv.telegramBotLoginAttemptLink(created.attemptId);
      if (link == null) {
        setState(() => _error = context.localized.oxplayerLoginBotNotConfigured);
        return;
      }
      setState(() {
        _attemptId = created.attemptId;
        _loginCode = created.code;
        _telegramLink = link;
      });
      unawaited(_pollForCompletion(userOpenedTelegram: false));
    } on OxplayerLoginAttemptException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  bool _isTv(BuildContext context) {
    final leanBack = ref.read(argumentsStateProvider).leanBackMode;
    return leanBack || AdaptiveLayout.viewSizeOf(context) == ViewSize.television;
  }

  Future<void> _openTelegramOnThisDevice() async {
    if (_isTv(context)) return;
    final link = _telegramLink;
    if (link != null) {
      if (kIsWeb) {
        await urilauncher.launchUrl(Uri.parse(link), webOnlyWindowName: '_blank');
      } else {
        unawaited(launchUrl(context, link));
      }
    }
    if (!_pollRunning) {
      unawaited(_pollForCompletion(userOpenedTelegram: true));
    } else if (mounted) {
      setState(() => _waiting = true);
    }
  }

  Future<void> _signInAsTestAccount() async {
    if (_testSignInInProgress) return;
    setState(() => _testSignInInProgress = true);
    try {
      await oxplayerSignInAsTestAccount(
        ref: ref,
        context: context,
        onSuccess: widget.onSuccess,
      );
    } finally {
      if (mounted) setState(() => _testSignInInProgress = false);
    }
  }

  Future<void> _pollForCompletion({required bool userOpenedTelegram}) async {
    if (_pollRunning) {
      if (userOpenedTelegram && !_isTv(context) && mounted) {
        setState(() => _waiting = true);
      }
      return;
    }
    final attemptId = _attemptId;
    final deviceId = _deviceId();
    if (attemptId == null || deviceId == null) return;

    _pollRunning = true;
    _cancelPoll = false;
    if (mounted) {
      setState(() {
        _waiting = userOpenedTelegram && !_isTv(context);
        _error = null;
      });
    }

    try {
      final poll = await _api.pollUntilComplete(
        attemptId: attemptId,
        deviceId: deviceId,
        shouldContinue: () => !_cancelPoll,
      );
      if (poll.isPending) {
        if (!mounted) return;
        setState(() {
          _waiting = false;
          _error = context.localized.oxplayerLoginTimedOutTryAgain;
        });
        return;
      }
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(ref, poll);
      if (response?.isSuccessful == true && response?.body != null) {
        await widget.onSuccess();
        if (mounted) {
          setState(() {
            _waiting = false;
            _error = null;
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _waiting = false;
        _error = context.localized.oxplayerLoginFailedTryCode;
      });
    } on OxplayerLoginAttemptException catch (e) {
      if (mounted) {
        setState(() {
          _waiting = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _waiting = false;
          _error = context.localized.oxplayerLoginConnectionError;
        });
      }
    } finally {
      _pollRunning = false;
    }
  }

  Widget _buildLoginCode(BuildContext context, {required bool isTv}) {
    final l10n = context.localized;
    final theme = Theme.of(context);
    final code = _loginCode;
    if (code == null) {
      if (_error == null) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return const SizedBox.shrink();
    }

    final codeText = Text(
      code,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        letterSpacing: 6,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      textAlign: TextAlign.center,
      semanticsLabel: code,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.oxplayerLoginCodeTitle,
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.oxplayerLoginCodeHint,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        if (isTv)
          Center(child: codeText)
        else
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                codeText,
                const SizedBox(width: 4),
                IconButton(
                  tooltip: l10n.oxplayerLoginCodeCopy,
                  onPressed: () => context.copyToClipboard(code),
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.localized;
    final theme = Theme.of(context);
    final link = _telegramLink;
    final bot = OxplayerEnv.botUsername;
    final viewSize = AdaptiveLayout.viewSizeOf(context);
    final isTv = _isTv(context);
    final isPhone = viewSize == ViewSize.phone;
    final showInlineQr = !isPhone;
    final showDeviceButton = !isTv;
    final showWaitingOnDevice = _waiting && showDeviceButton;
    final deviceButtonLabel = showWaitingOnDevice
        ? l10n.oxplayerLoginWaitingTelegram
        : kIsWeb
            ? l10n.oxplayerLoginWithTelegramWeb
            : l10n.oxplayerLoginOpenTelegramDevice;

    final subtitle = showWaitingOnDevice
        ? l10n.oxplayerLoginWaitingApprovalTitle
        : isTv
            ? l10n.oxplayerLoginTvSubtitle
            : kIsWeb
                ? (isPhone ? l10n.oxplayerLoginWebPhoneSubtitle : l10n.oxplayerLoginWebDesktopSubtitle)
                : (isPhone ? l10n.oxplayerLoginMobilePhoneSubtitle : l10n.oxplayerLoginMobileDesktopSubtitle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.oxplayerLoginTelegramTitle,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _buildLoginCode(context, isTv: isTv),
        if (showInlineQr) ...[
          const SizedBox(height: 20),
          if (link != null)
            Center(
              child: OxplayerTestAccountQrHold(
                enabled: !_testSignInInProgress && !_waiting,
                onHoldComplete: _signInAsTestAccount,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: QrImageView(
                    data: link,
                    size: 200,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            )
          else if (_error == null && _loginCode == null)
            const Center(child: CircularProgressIndicator())
          else
            const SizedBox(height: 200),
        ],
        if (showDeviceButton) ...[
          const SizedBox(height: 20),
          if (isPhone)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: link == null ? null : _openTelegramOnThisDevice,
                    icon: showWaitingOnDevice
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.telegram),
                    label: Text(
                      deviceButtonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (link != null)
                  IconButton(
                    tooltip: l10n.oxplayerHelpQrCaption,
                    onPressed: showWaitingOnDevice
                        ? null
                        : () => showOxplayerBotQrSheet(
                              context,
                              telegramLink: link,
                              botUsername: bot,
                              onQrHoldComplete: _signInAsTestAccount,
                              qrHoldEnabled: !_testSignInInProgress && !_waiting,
                            ),
                    icon: const Icon(Icons.qr_code_2_rounded),
                  ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: link == null ? null : _openTelegramOnThisDevice,
              icon: showWaitingOnDevice
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.telegram),
              label: Text(
                deviceButtonLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pollRunning
                ? null
                : () async {
                    if (_attemptId != null && _telegramLink != null) {
                      await _pollForCompletion(userOpenedTelegram: true);
                    } else {
                      await _startAttempt();
                    }
                  },
            child: Text(l10n.oxplayerLoginTryAgain),
          ),
        ],
        if (bot != null) ...[
          const SizedBox(height: 16),
          Text(
            '@$bot',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
