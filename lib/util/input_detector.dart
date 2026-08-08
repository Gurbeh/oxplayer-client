import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_helper.dart';

class InputDetector extends StatefulWidget {
  final bool isDesktop;
  final bool htpcMode;
  /// Android TV / Leanback — keep dPad switching. Phone/tablet OX must not, or
  /// one arrow key + default `useSystemIME=false` makes OutlinedTextField readOnly
  /// and IgnorePointer blocks the login phone field.
  final bool leanBackMode;
  final Widget Function(InputDevice input) child;

  const InputDetector({
    super.key,
    required this.isDesktop,
    required this.htpcMode,
    this.leanBackMode = false,
    required this.child,
  });

  @override
  State<InputDetector> createState() => _InputDetectorState();
}

class _InputDetectorState extends State<InputDetector> {
  late InputDevice _currentInput = widget.htpcMode || widget.leanBackMode
      ? InputDevice.dPad
      : (widget.isDesktop || kIsWeb)
          ? InputDevice.pointer
          : InputDevice.touch;

  /// OX phone/tablet/emulator: stay on touch/pointer so login TextFields stay editable.
  bool get _oxLockTouchInput =>
      OxplayerConfig.isEnabled && !widget.htpcMode && !widget.leanBackMode;

  @override
  void initState() {
    super.initState();
    _startListeningToKeyboard();
  }

  void _startListeningToKeyboard() {
    ServicesBinding.instance.keyboard.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_handleKeyPress);
    super.dispose();
  }

  bool _handleKeyPress(KeyEvent event) {
    if (_oxLockTouchInput) return false;

    if (event is KeyDownEvent) {
      if (isEditableTextFocused() &&
          (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight)) {
        return false;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.select) {
        _updateInputDevice(InputDevice.dPad);
      }
    }
    return false;
  }

  void _handlePointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (event.kind == PointerDeviceKind.touch) {
        _updateInputDevice(InputDevice.touch);
      } else if (event.kind == PointerDeviceKind.mouse) {
        _updateInputDevice(InputDevice.pointer);
      }
    }
  }

  void _updateInputDevice(InputDevice device) {
    if (_oxLockTouchInput && device == InputDevice.dPad) return;
    if (_currentInput != device) {
      // Only clear focus when leaving D-pad (TV) mode.
      // touch↔pointer switches are common on Android emulators (mouse click) — unfocusing
      // there steals TextField focus so the laptop keyboard never types into the field.
      if (_currentInput == InputDevice.dPad && device != InputDevice.dPad) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() {
        _currentInput = device;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerEvent,
      behavior: HitTestBehavior.translucent,
      child: IgnorePointer(
        ignoring: _currentInput == InputDevice.dPad && !_oxLockTouchInput,
        child: Builder(
          builder: (context) => widget.child(_currentInput),
        ),
      ),
    );
  }
}
