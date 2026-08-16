import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps D-pad / remote focus inside a modal.
///
/// Home poster rows call [FocusNode.requestFocus] after layout (see
/// `horizontal_list.dart`), which steals primary focus from [showDialog]
/// even when the route is modal.
class OxDialogFocusTrap extends StatefulWidget {
  const OxDialogFocusTrap({
    required this.child,
    this.primaryFocus,
    super.key,
  });

  final Widget child;
  final FocusNode? primaryFocus;

  @override
  State<OxDialogFocusTrap> createState() => _OxDialogFocusTrapState();
}

class _OxDialogFocusTrapState extends State<OxDialogFocusTrap> {
  final FocusScopeNode _scope =
      FocusScopeNode(debugLabel: 'OxDialogFocusTrap');
  Timer? _reclaimTimer;
  bool _reclaimScheduled = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_reclaim);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reclaim());
    // Poster rows mount over several frames after splash → home.
    _reclaimTimer = Timer.periodic(const Duration(milliseconds: 160), (timer) {
      _reclaim();
      if (timer.tick >= 20) timer.cancel();
    });
  }

  void _reclaim() {
    if (!mounted || _reclaimScheduled) return;
    if (_scope.hasFocus) return;
    _reclaimScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reclaimScheduled = false;
      if (!mounted || _scope.hasFocus) return;

      final primary = widget.primaryFocus;
      if (primary != null && primary.canRequestFocus) {
        _scope.requestFocus(primary);
        return;
      }

      FocusNode? next;
      for (final node in _scope.traversalDescendants) {
        if (node.canRequestFocus && node.context != null) {
          next = node;
          break;
        }
      }
      if (next != null) {
        _scope.requestFocus(next);
        return;
      }
      if (_scope.canRequestFocus) {
        _scope.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _reclaimTimer?.cancel();
    FocusManager.instance.removeListener(_reclaim);
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: _scope,
      autofocus: true,
      child: widget.child,
    );
  }
}
