import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps D-pad / remote focus inside a modal for as long as it is open.
///
/// Home poster rows call [FocusNode.requestFocus] after layout (see
/// `horizontal_list.dart` / [FocusButton]). That bypasses the modal route and
/// moves primary focus to the screen behind the dialog. Checking
/// [FocusScopeNode.hasFocus] is not enough — this trap:
/// 1. Detects when [FocusManager.primaryFocus] is outside the dialog
/// 2. Disables that foreign [FocusScopeNode] so later `requestFocus` calls no-op
/// 3. Moves focus back onto the dialog action
class OxDialogFocusTrap extends StatefulWidget {
  const OxDialogFocusTrap({
    required this.child,
    this.primaryFocus,
    super.key,
  });

  final Widget child;
  final FocusNode? primaryFocus;

  static int _active = 0;

  /// True while an [OxDialogFocusTrap] is in the tree.
  static bool get isActive => _active > 0;

  @override
  State<OxDialogFocusTrap> createState() => _OxDialogFocusTrapState();
}

class _OxDialogFocusTrapState extends State<OxDialogFocusTrap> {
  Timer? _poll;
  bool _ensuring = false;
  final _locked = <FocusScopeNode, ({bool canRequest, bool descendants})>{};

  @override
  void initState() {
    super.initState();
    OxDialogFocusTrap._active++;
    FocusManager.instance.addListener(_ensure);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
    _poll = Timer.periodic(const Duration(milliseconds: 80), (_) => _ensure());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    FocusScope.of(context).traversalEdgeBehavior =
        TraversalEdgeBehavior.closedLoop;
  }

  bool _onKey(KeyEvent event) {
    _ensure();
    return false;
  }

  bool _owns(FocusNode? node) {
    if (node == null) return false;
    if (identical(node, widget.primaryFocus)) return true;
    final ctx = node.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<_OxDialogFocusTrapState>() == this;
  }

  bool _scopeContainsUs(FocusScopeNode scope) {
    final ours = FocusScope.of(context);
    return identical(scope, ours) || ours.ancestors.contains(scope);
  }

  void _ensure() {
    if (!mounted || _ensuring) return;
    _ensuring = true;
    try {
      final primary = FocusManager.instance.primaryFocus;
      if (_owns(primary)) return;

      if (primary != null) {
        _lockForeignScope(primary);
      }
      _focusSelf();
    } finally {
      _ensuring = false;
    }
  }

  void _lockForeignScope(FocusNode thief) {
    final scope = thief.enclosingScope;
    if (scope == null) return;
    if (identical(scope, FocusManager.instance.rootScope)) return;
    if (_scopeContainsUs(scope)) return;
    if (_locked.containsKey(scope)) return;

    _locked[scope] = (
      canRequest: scope.canRequestFocus,
      descendants: scope.descendantsAreFocusable,
    );
    scope.canRequestFocus = false;
    scope.descendantsAreFocusable = false;
  }

  void _focusSelf() {
    final node = widget.primaryFocus;
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
      return;
    }
    if (!mounted) return;
    final scope = FocusScope.of(context);
    for (final child in scope.traversalDescendants) {
      if (child.canRequestFocus && child.context != null && _owns(child)) {
        child.requestFocus();
        return;
      }
    }
  }

  void _unlock() {
    for (final entry in _locked.entries) {
      entry.key.canRequestFocus = entry.value.canRequest;
      entry.key.descendantsAreFocusable = entry.value.descendants;
    }
    _locked.clear();
  }

  @override
  void dispose() {
    _poll?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_ensure);
    _unlock();
    OxDialogFocusTrap._active--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: widget.child,
    );
  }
}
