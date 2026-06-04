import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_qr_hold.dart';
import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';

class OxplayerTelegramLoginPanel extends ConsumerStatefulWidget {
  const OxplayerTelegramLoginPanel({
    required this.onSuccess,
    required this.onManualCode,
    super.key,
  });

  final Future<void> Function() onSuccess;
  final VoidCallback onManualCode;

  @override
  ConsumerState<OxplayerTelegramLoginPanel> createState() => _OxplayerTelegramLoginPanelState();
}

class _OxplayerTelegramLoginPanelState extends ConsumerState<OxplayerTelegramLoginPanel>
    with WidgetsBindingObserver {
  final _api = OxplayerLoginAttemptApi();
  String? _attemptId;
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
    if (state == AppLifecycleState.resumed && _waiting && mounted) {
      setState(() {});
    }
  }

  String? _deviceId() {
    final creds = ref.read(authProvider).serverLoginModel?.tempCredentials;
    return creds?.deviceId;
  }

  Future<void> _startAttempt() async {
    final deviceId = _deviceId();
    if (deviceId == null || deviceId.isEmpty) {
      setState(() => _error = 'Device not ready. Pull to retry.');
      return;
    }
    setState(() {
      _error = null;
      _waiting = false;
      _attemptId = null;
      _telegramLink = null;
    });
    try {
      final created = await _api.createAttempt(deviceId: deviceId);
      if (!mounted) return;
      final link = OxplayerEnv.telegramBotLoginAttemptLink(created.attemptId);
      if (link == null) {
        setState(() => _error = 'Telegram bot is not configured.');
        return;
      }
      setState(() {
        _attemptId = created.attemptId;
        _telegramLink = link;
      });
      // Poll in background so scanning the QR on another phone still signs in here.
      unawaited(_pollForCompletion(userOpenedTelegram: false));
    } on OxplayerLoginAttemptException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _openTelegramOnThisDevice() async {
    final link = _telegramLink;
    if (link != null) {
      unawaited(launchUrl(context, link));
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
      if (userOpenedTelegram && mounted) {
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
        _waiting = userOpenedTelegram;
        _error = null;
      });
    }

    try {
      final poll = await _api.pollUntilComplete(
        attemptId: attemptId,
        deviceId: deviceId,
        shouldContinue: () => mounted && !_cancelPoll,
      );
      if (!mounted) return;
      if (poll.isPending) {
        setState(() {
          _waiting = false;
          _error = 'Timed out. Approve in Telegram, then tap Try again.';
        });
        return;
      }
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(ref, poll);
      if (!mounted) return;
      if (response?.isSuccessful != true || response?.body == null) {
        setState(() {
          _waiting = false;
          _error = 'Sign-in failed. Try again or use a login code.';
        });
        return;
      }
      await widget.onSuccess();
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
          _error = 'Connection error. Stay on this screen after approving, or tap Try again.';
        });
      }
    } finally {
      _pollRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _telegramLink;
    final bot = OxplayerEnv.botUsername;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in with Telegram',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _waiting
              ? 'Waiting for approval in Telegram… This screen will sign you in automatically.'
              : 'Scan the QR with another device, or tap the button to open Telegram on this phone.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
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
        else if (_error == null)
          const Center(child: CircularProgressIndicator())
        else
          const SizedBox(height: 200),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: link == null ? null : _openTelegramOnThisDevice,
          icon: _waiting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.telegram),
          label: Text(_waiting ? 'Waiting for Telegram…' : 'Open Telegram on this device'),
        ),
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
            child: const Text('Try again'),
          ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: _waiting ? null : widget.onManualCode,
          child: Text(
            "Couldn't sign in this way? Enter a login code manually",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        if (bot != null) ...[
          const SizedBox(height: 4),
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
