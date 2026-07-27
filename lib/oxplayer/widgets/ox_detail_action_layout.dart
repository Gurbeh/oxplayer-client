import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// TV d-pad: linear [Row] focus order. Touch/desktop: [Wrap] layout.
class OxDetailActionLayout extends StatelessWidget {
  final WrapAlignment alignment;
  final List<Widget> children;

  const OxDetailActionLayout({
    required this.alignment,
    required this.children,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final useRow = OxplayerConfig.isEnabled && AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    if (useRow) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: children,
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
