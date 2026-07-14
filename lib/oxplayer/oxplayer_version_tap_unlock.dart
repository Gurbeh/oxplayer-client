import 'package:flutter/material.dart';

/// Unlocks [onUnlocked] after [requiredTaps] quick taps on [child].
class OxplayerVersionTapUnlock extends StatefulWidget {
  const OxplayerVersionTapUnlock({
    required this.child,
    required this.onUnlocked,
    this.requiredTaps = 8,
    super.key,
  });

  final Widget child;
  final VoidCallback onUnlocked;
  final int requiredTaps;

  @override
  State<OxplayerVersionTapUnlock> createState() => _OxplayerVersionTapUnlockState();
}

class _OxplayerVersionTapUnlockState extends State<OxplayerVersionTapUnlock> {
  static const _tapWindow = Duration(seconds: 3);

  int _tapCount = 0;
  DateTime? _lastTapAt;

  void _onTap() {
    final now = DateTime.now();
    if (_lastTapAt != null && now.difference(_lastTapAt!) > _tapWindow) {
      _tapCount = 0;
    }
    _lastTapAt = now;
    _tapCount++;
    if (_tapCount >= widget.requiredTaps) {
      _tapCount = 0;
      _lastTapAt = null;
      widget.onUnlocked();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
