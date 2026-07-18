import 'package:flutter/material.dart';

/// Bundled Iran flag image (round PNG, not Unicode emoji).
class OxIranFlagIcon extends StatelessWidget {
  final double size;

  const OxIranFlagIcon({this.size = 22, super.key});

  static const assetPath = 'assets/oxplayer/flags/iran_android.png';

  @override
  Widget build(BuildContext context) {
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 96);
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: cachePx,
      cacheHeight: cachePx,
    );
  }
}
