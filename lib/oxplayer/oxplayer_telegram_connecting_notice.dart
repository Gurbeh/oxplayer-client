import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// The "we are still working, don't leave" state for Telegram sign-in.
///
/// Replaces the bare spinner the login panels used to show while the MTProto connection came up.
/// On a slow network that spinner sat silent for ~20s (measured on an Android TV: 18s for the very
/// first connect, which has to discover the data centre before it can do anything), with no
/// indication of progress — so the natural reaction was to press Back or kill the app, which threw
/// away the connection that was seconds from being ready.
///
/// Two things fix that, and both matter:
///  - saying what is happening, and that it can legitimately take a while;
///  - a running seconds counter, so the screen is visibly alive. A static spinner on a TV is
///    indistinguishable from a frozen one.
class OxplayerTelegramConnectingNotice extends StatefulWidget {
  const OxplayerTelegramConnectingNotice({
    super.key,
    this.compact = false,
  });

  /// Tighter padding for use inside an already-busy panel.
  final bool compact;

  @override
  State<OxplayerTelegramConnectingNotice> createState() => _OxplayerTelegramConnectingNoticeState();
}

class _OxplayerTelegramConnectingNoticeState extends State<OxplayerTelegramConnectingNotice> {
  final _controller = OxplayerTdlibBridgeController.instance();
  Timer? _ticker;
  DateTime _since = DateTime.now();
  int _elapsedSeconds = 0;

  /// Set on a blocked Back press; the next one within [_confirmExitWindow] is allowed through.
  DateTime? _backPressedAt;

  /// Below this the counter is noise — a fast connect is over before it would help.
  static const _showCounterAfter = 5;

  /// How long the "press Back again" offer stays open. Long enough to read the warning on a TV
  /// from across a room, short enough that a Back press minutes later is not silently treated as
  /// confirmation of something the user has forgotten about.
  static const _confirmExitWindow = Duration(seconds: 5);

  bool get _awaitingExitConfirm {
    final at = _backPressedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _confirmExitWindow;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds = DateTime.now().difference(_since).inSeconds);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // Restart the clock on every health transition so the number always describes the attempt in
    // progress, not the total time the panel has been on screen.
    setState(() {
      _since = DateTime.now();
      _elapsedSeconds = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = _controller.connectionHealth;
    final degraded = health == OxTdlibConnectionHealth.degraded;

    final headline = degraded ? 'Reconnecting to Telegram…' : 'Connecting to Telegram…';
    final detail = degraded
        ? "Your sign-in is still valid — only the connection dropped. This usually recovers on its own."
        : 'The first connection can take up to a minute on some networks. '
            'Please keep the app open and let it finish.';

    // Guards against throwing away a connection that is seconds from ready, without ever trapping
    // anyone: the second Back always leaves. A hard block would be worse than the problem on a TV,
    // where Back is the only way out of a screen.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_awaitingExitConfirm) {
          Navigator.of(context).pop();
          return;
        }
        setState(() => _backPressedAt = DateTime.now());
      },
      child: _buildBody(context, theme, headline, detail),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme, String headline, String detail) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.compact ? 20 : 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            headline,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (_elapsedSeconds >= _showCounterAfter) ...[
            const SizedBox(height: 12),
            Text(
              '${_elapsedSeconds}s',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          // Rendered inline rather than as a SnackBar: this screen is used on a TV, where a
          // bottom-anchored transient toast is easy to miss and cannot be focused.
          if (_awaitingExitConfirm) ...[
            const SizedBox(height: 16),
            Text(
              'Still connecting — press Back again to leave.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
