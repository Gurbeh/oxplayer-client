import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/oxplayer/oxplayer_delivery_reader_sync.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_jellyfin_auth.dart';
import 'package:fladder/oxplayer/oxplayer_login_attempt_api.dart';
import 'package:fladder/oxplayer/oxplayer_main_bot_login_api.dart';
import 'package:fladder/oxplayer/oxplayer_ox_login_kind_store.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_connecting_experience.dart';
import 'package:fladder/theme.dart';

/// Sign-in via @main-bot instead of TDLib phone/QR — for users who don't want to give OXPlayer
/// access to their personal Telegram account. The user approves a login attempt in Telegram
/// (tapping the deep-link/QR opens the bot with a Yes/No prompt, or they type the code shown
/// here into the bot); once approved, this polls the same way the TDLib flow polls
/// /auth/telegram — see oxplayer-be apps/api/internal/server/auth_login_attempt.go.
///
/// This does NOT log the native Telegram bridge into the user's own account at all. Right after
/// the OX session is established, it separately tries to fetch+apply a personal bot token (set
/// via /connectbot in Telegram) so native playback works — if that isn't set up yet, sign-in
/// still succeeds; playback will just prompt the user to finish /connectbot when they try to
/// play something (see apps/api's forwardPublicPlaybackToUserBot error message).
class OxplayerMainBotLoginPanel extends ConsumerStatefulWidget {
  const OxplayerMainBotLoginPanel({required this.onSuccess, this.onBack, super.key});

  final Future<void> Function() onSuccess;
  final VoidCallback? onBack;

  @override
  ConsumerState<OxplayerMainBotLoginPanel> createState() => _OxplayerMainBotLoginPanelState();
}

class _OxplayerMainBotLoginPanelState extends ConsumerState<OxplayerMainBotLoginPanel> {
  final _api = OxplayerMainBotLoginApi();
  OxplayerLoginAttemptStart? _attempt;
  String? _error;
  bool _starting = true;
  bool _finishing = false;
  int _pollGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollGeneration++; // stop any in-flight poll loop from acting after unmount
    super.dispose();
  }

  /// [silent]: background auto-refresh (see _pollLoop) — swap in a fresh code/QR without
  /// flashing the full loading spinner, same idea as a QR code that quietly rotates itself.
  Future<void> _start({bool silent = false}) async {
    setState(() {
      _starting = !silent;
      _error = null;
    });
    final generation = ++_pollGeneration;
    try {
      final identity = await OxplayerTdlibBridgeController.resolveDeviceIdentity();
      final attempt = await _api.createAttempt(deviceId: identity);
      if (!mounted || generation != _pollGeneration) return;
      setState(() {
        _attempt = attempt;
        _starting = false;
      });
      unawaited(_pollLoop(attempt, identity, generation));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        // Clear rather than leave a stale QR/code on screen next to the error — this only
        // reaches the user after createAttempt itself repeatedly failed (see _pollLoop), so any
        // previously-shown attempt is either already spent or about to be, and re-showing it
        // would invite tapping "Open Telegram to approve" on something dead.
        _attempt = null;
        _error = e is OxplayerLoginAttemptException ? e.message : 'Could not start sign-in';
      });
    }
  }

  /// Refresh this far ahead of expiry — comfortably longer than one poll()'s ~55s server-side
  /// long-poll cycle, so a refresh is never raced by a call that was already in flight.
  static const _refreshMargin = Duration(seconds: 75);

  Future<void> _pollLoop(OxplayerLoginAttemptStart attempt, String deviceId, int generation) async {
    final deadline = DateTime.now().add(Duration(seconds: attempt.expiresIn));
    var consecutiveFailures = 0;
    while (mounted && generation == _pollGeneration) {
      if (deadline.difference(DateTime.now()) <= _refreshMargin) {
        // Like a QR code on a device-linking screen, mint a fresh one before this one goes
        // stale rather than making the user notice it expired and tap Retry themselves.
        unawaited(_start(silent: true));
        return;
      }
      try {
        final result = await _api.poll(attemptId: attempt.attemptId, deviceId: deviceId);
        if (!mounted || generation != _pollGeneration) return;
        consecutiveFailures = 0;
        if (result.isPending) continue; // server itself long-polled ~55s already
        await _finish(result);
        return;
      } catch (e) {
        if (!mounted || generation != _pollGeneration) return;
        // The user is normally mid-flow here — off in Telegram approving, then off in
        // BotFather creating a bot, which easily takes minutes and regularly causes the app to
        // be backgrounded (a transient network/socket error on resume, not a real failure) —
        // and if they take long enough, the attempt itself can go stale server-side
        // (expired/not-found/already-used, surfaced as OxplayerLoginAttemptException). Both are
        // expected here, not user error: retry a few times with backoff, then fall back to
        // silently minting a fresh attempt (same as the pre-emptive refresh above) instead of
        // ever dead-ending on a "Retry" button showing a now-possibly-stale QR/code — reported
        // as a real bug (approve link said "expired" after the round trip, with no way back
        // except noticing a small text link).
        consecutiveFailures++;
        if (consecutiveFailures <= 6) {
          await Future<void>.delayed(Duration(seconds: consecutiveFailures.clamp(1, 5)));
          continue;
        }
        unawaited(_start(silent: true));
        return;
      }
    }
  }

  Future<void> _finish(OxplayerLoginAttemptPollResult result) async {
    setState(() => _finishing = true);
    try {
      final response = await oxplayerAuthenticateFromLoginAttemptPoll(
        ref,
        result,
        loginKind: OxplayerOxLoginKind.bot,
      );
      final account = response?.body;
      if (account == null) {
        throw StateError('Sign-in did not complete');
      }
      await _applyBotTokenIfConnected(account.credentials.token);
      await widget.onSuccess();
    } catch (e) {
      // The server already consumed this attempt (that's how we got a completed `result` to
      // apply) — it can't be retried, so the only real recovery is a whole new attempt. Restart
      // automatically rather than leaving the user stuck on a dead QR/code they'd have to
      // notice needs a manual Retry tap.
      if (mounted) {
        setState(() => _finishing = false);
        unawaited(_start());
      }
    }
  }

  /// Best-effort — playback (not sign-in) is what actually needs this, and it re-checks with a
  /// clear in-app message if the user hasn't finished /connectbot yet.
  Future<void> _applyBotTokenIfConnected(String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) return;
    try {
      await oxplayerEnsureTdlibMatchesOxUser(accessToken);
    } catch (_) {
      // Non-fatal — play path re-checks and surfaces /connectbot if still missing.
    }
  }

  Future<void> _openBot() async {
    final id = _attempt?.attemptId;
    if (id == null) return;
    final link = OxplayerEnv.telegramBotLoginAttemptLink(id);
    if (link == null) return;
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_finishing || _starting) {
      // Both states are the same underlying wait from the user's perspective: _starting is
      // before an attempt link can even be requested, _finishing is applying the bot token
      // after approval — see the widget's doc for why this needs to be more than a spinner.
      return const OxplayerTdlibConnectingExperience();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in with @${OxplayerEnv.botUsername ?? "main-bot"}',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          "Approve sign-in in Telegram — OXPlayer never sees your Telegram account.",
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_attempt != null) ...[
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: OxplayerEnv.telegramBotLoginAttemptLink(_attempt!.attemptId) ?? '',
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            autofocus: true,
            style: FilledButton.styleFrom(
              shape: FladderTheme.largeShape,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _openBot,
            icon: const Icon(IconsaxPlusLinear.send_2),
            label: const Text('Open Telegram to approve'),
          ),
          const SizedBox(height: 14),
          Text(
            'Or type this code into @${OxplayerEnv.botUsername ?? "main-bot"} in Telegram:',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          SelectableText(
            _attempt!.code,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              letterSpacing: 6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (widget.onBack != null) ...[
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(IconsaxPlusLinear.arrow_left_2, size: 18),
            label: const Text('Use my Telegram account instead'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => unawaited(_start()), child: const Text('Retry')),
        ],
      ],
    );
  }
}
