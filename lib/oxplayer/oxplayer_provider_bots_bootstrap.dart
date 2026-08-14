import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/oxplayer/oxplayer_telegram_delivery_api.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Prepares every delivery sender on the user's Telegram account: started (so the bot may message
/// them at all), muted, and filed in Archive.
///
/// This is what keeps delivery copies out of the user's inbox. Warming a dashboard row asks the
/// backend to copy a dozen videos into a DM; without this the user would watch their Telegram fill
/// up with videos they never requested.
///
/// The sender list comes from the API rather than the build, so ops can add or retire a bot without
/// an app release — which is also why this runs on every app enter and not only after login: a
/// sender added yesterday must be started by a user who has not logged in since.
///
/// Session accounts only. A bot-token login is not a user account (no dialog list, no notification
/// settings) and its DM was already opened by main-bot's /connectbot; the native side no-ops there.
abstract final class OxplayerProviderBotsBootstrap {
  /// Guards against the several dashboard rebuilds one app enter produces. Cleared by [reset] on
  /// logout/account switch so the next user's session prepares its own senders.
  static Future<void>? _inFlight;
  static bool _done = false;
  static bool _listening = false;

  /// Fire-and-forget for app-enter. Prefetch and play must [ensureReady] so they cannot copy into
  /// a DM the user has not started yet.
  static void schedule() {
    unawaited(ensureReady());
  }

  /// Completes after start+mute+archive (or immediately if that already ran this launch).
  /// Returns false when the Telegram session is not ready yet — caller must not copy.
  static Future<bool> ensureReady() async {
    if (!OxplayerConfig.isEnabled) return true;
    _listenForReady();
    if (_done) return true;
    final inFlight = _inFlight;
    if (inFlight != null) {
      await inFlight;
      return _done;
    }
    final future = _run();
    _inFlight = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
    return _done;
  }

  /// Forgets that this launch already ran, so a different account prepares its own senders.
  static void reset() {
    _done = false;
    _inFlight = null;
  }

  static void _listenForReady() {
    if (_listening) return;
    _listening = true;
    final controller = OxplayerTdlibBridgeController.instance();
    controller.addListener(() {
      if (controller.state.kind == OxTdlibAuthStateKind.ready && !_done && _inFlight == null) {
        schedule();
      }
    });
  }

  static Future<void> _run() async {
    try {
      final bots = await OxplayerTelegramDeliveryApi.providerBots();
      if (bots.isEmpty) {
        // Either the backend has no senders configured or the call failed. Both are worth one more
        // attempt on the next app enter, so this is deliberately not marked done.
        debugPrint('OXPLAY_TDLIB: no provider bots to prepare');
        return;
      }
      final ok = await OxplayerTdlibBridgeController.instance().ensureProviderBotsReady(bots);
      if (ok) {
        _done = true;
      } else {
        debugPrint('OXPLAY_TDLIB: provider bot bootstrap deferred — session not ready yet');
      }
    } catch (e) {
      debugPrint('OXPLAY_TDLIB: provider bot bootstrap failed: $e');
    }
  }
}
