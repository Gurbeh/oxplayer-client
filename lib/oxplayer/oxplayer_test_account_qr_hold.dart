import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/oxplayer/oxplayer_test_account_sign_in.dart';

/// Press and hold [child] (login QR) for [kOxTestAccountQrHoldDuration] to trigger tester sign-in.
/// Touch/mouse and TV remote OK/Select long-press are supported.
class OxplayerTestAccountQrHold extends StatefulWidget {
  const OxplayerTestAccountQrHold({
    required this.child,
    required this.onHoldComplete,
    this.enabled = true,
    this.autofocus = false,
    super.key,
  });

  final Widget child;
  final VoidCallback onHoldComplete;
  final bool enabled;
  /// When true (Android TV), the QR receives initial D-pad focus for reviewer long-press.
  final bool autofocus;

  @override
  State<OxplayerTestAccountQrHold> createState() => _OxplayerTestAccountQrHoldState();
}

class _OxplayerTestAccountQrHoldState extends State<OxplayerTestAccountQrHold> {
  Timer? _holdTimer;
  final FocusNode _focusNode = FocusNode(debugLabel: 'oxTestAccountQrHold');
  bool _focused = false;

  @override
  void dispose() {
    _cancelHold();
    _focusNode.dispose();
    super.dispose();
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _startHold() {
    if (!widget.enabled || _holdTimer != null) return;
    _holdTimer = Timer(kOxTestAccountQrHoldDuration, () {
      _holdTimer = null;
      if (!mounted) return;
      widget.onHoldComplete();
    });
  }

  bool _isActivateKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (!_isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _startHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _cancelHold();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: (_) => _startHold(),
        onPointerUp: (_) => _cancelHold(),
        onPointerCancel: (_) => _cancelHold(),
        child: DecoratedBox(
          decoration: _focused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary, width: 3),
                )
              : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}
