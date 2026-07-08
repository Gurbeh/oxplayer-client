import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/widgets/ox_skeleton_box.dart';

/// Play-button-shaped skeleton for detail screens while item data loads.
class OxMediaPlayButtonSkeleton extends StatelessWidget {
  const OxMediaPlayButtonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const OxSkeletonBox(
      width: 148,
      height: 44,
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
  }
}
