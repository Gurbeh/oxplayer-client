import 'package:flutter/material.dart';

/// Bundled Iran flag image (round PNG, not Unicode emoji).
class OxIranFlagIcon extends StatelessWidget {
  final double size;

  const OxIranFlagIcon({this.size = 22, super.key});

  static const assetPath = 'assets/oxplayer/flags/flag_of_iran_round.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
  }
}
