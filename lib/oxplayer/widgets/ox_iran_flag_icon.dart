import 'package:flutter/material.dart';

/// Small Iran flag for metadata rows and subtitle pickers ([iran_splash_256.png]).
class OxIranFlagIcon extends StatelessWidget {
  final double size;

  const OxIranFlagIcon({this.size = 22, super.key});

  static const assetPath = 'assets/oxplayer/flags/iran_splash_256.png';

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
