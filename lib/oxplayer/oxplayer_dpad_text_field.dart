import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';

/// TV-friendly text field with a thick focus ring.
///
/// [useSystemIme]: when true (default), Select/OK opens the Android TV system keyboard.
/// When false, uses Fladder's slide-in mini keyboard.
class OxplayerDpadTextField extends StatefulWidget {
  const OxplayerDpadTextField({
    required this.controller,
    required this.label,
    this.focusNode,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.done,
    this.inputFormatters,
    this.style,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
    this.obscureText = false,
    this.autofillHints,
    this.useSystemIme = true,
    this.enabled = true,
    this.onChanged,
    this.onKeyboardClosed,
    this.onMoveFocusDown,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final TextAlign textAlign;
  final bool autofocus;
  final bool obscureText;
  final Iterable<String>? autofillHints;

  /// Prefer Android system IME over Fladder mini keyboard (TV login default).
  final bool useSystemIme;

  /// When false (e.g. auth submit in flight), field + OK are inert.
  final bool enabled;

  final ValueChanged<String>? onChanged;

  /// Called after keyboard closes (custom KB) or after Done on system IME.
  final VoidCallback? onKeyboardClosed;

  /// D-pad Down while field focused and IME closed (e.g. move to Confirm).
  final VoidCallback? onMoveFocusDown;

  @override
  State<OxplayerDpadTextField> createState() => OxplayerDpadTextFieldState();
}

class OxplayerDpadTextFieldState extends State<OxplayerDpadTextField> {
  late final FocusNode _wrapperFocus = widget.focusNode ?? FocusNode();
  final FocusNode _textFocus = FocusNode();
  bool _hasFocus = false;
  bool _ownsFocus = false;

  bool get _isDpad => AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

  bool get _useCustomKb => _isDpad && !widget.useSystemIme;

  @override
  void initState() {
    super.initState();
    _ownsFocus = widget.focusNode == null;
    _wrapperFocus.addListener(_onFocusChange);
    _textFocus.addListener(_onFocusChange);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) requestFocus();
      });
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _wrapperFocus.hasFocus || _textFocus.hasFocus);
  }

  /// Focus wrapper (visible ring). Select then opens IME / custom keyboard.
  void requestFocus() {
    if (_isDpad) {
      _wrapperFocus.requestFocus();
    } else {
      _textFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _wrapperFocus.removeListener(_onFocusChange);
    _textFocus.removeListener(_onFocusChange);
    if (_ownsFocus) _wrapperFocus.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  void _showSystemIme() {
    _textFocus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  Future<void> _openCustomKeyboard() async {
    await openKeyboard(
      context,
      widget.controller,
      inputType: widget.keyboardType,
      inputAction: widget.textInputAction,
      onChanged: () {
        widget.onChanged?.call(widget.controller.text);
        if (mounted) setState(() {});
      },
    );
    if (!mounted) return;
    widget.onKeyboardClosed?.call();
    _wrapperFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_isDpad || !widget.enabled) return KeyEventResult.ignored;

    // System IME open: never steal arrows / Select from the on-screen keyboard.
    if (!_useCustomKb && MediaQuery.viewInsetsOf(context).bottom > 0) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.onMoveFocusDown != null) {
      if (_textFocus.hasFocus) {
        _textFocus.unfocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
      widget.onMoveFocusDown!();
      return KeyEventResult.handled;
    }

    if (acceptKeys.contains(event.logicalKey)) {
      if (_useCustomKb) {
        unawaited(_openCustomKeyboard());
      } else {
        _showSystemIme();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
    final enabled = widget.enabled;

    final textField = TextField(
      controller: widget.controller,
      focusNode: _textFocus,
      enabled: enabled,
      readOnly: _useCustomKb || !enabled,
      showCursor: enabled && !_useCustomKb,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      style: widget.style,
      textAlign: widget.textAlign,
      autofillHints: widget.autofillHints,
      enableSuggestions: false,
      autocorrect: false,
      canRequestFocus: enabled && !_useCustomKb,
      onTap: enabled && _isDpad
          ? () {
              if (_useCustomKb) {
                unawaited(_openCustomKeyboard());
              } else {
                _showSystemIme();
              }
            }
          : null,
      onChanged: enabled ? widget.onChanged : null,
      onSubmitted: enabled
          ? (_) {
              widget.onKeyboardClosed?.call();
            }
          : null,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: _hasFocus && enabled ? 3 : 2,
            color: _hasFocus && enabled ? theme.colorScheme.primary : Colors.transparent,
          ),
        ),
        child: Focus(
          focusNode: _wrapperFocus,
          canRequestFocus: enabled,
          onKeyEvent: _onKey,
          child: ExcludeFocusTraversal(child: textField),
        ),
      ),
    );
  }
}
