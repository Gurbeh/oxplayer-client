import 'package:flutter/material.dart';

/// OX splash branding — same asset/size as native Android splash ([iran_android.png]).
class OxSplashBrand extends StatelessWidget {
  const OxSplashBrand({super.key});

  static const assetPath = 'assets/oxplayer/flags/iran_android.png';

  /// Matches source PNG (265×265). Keep in sync with native splash + precache.
  static const displaySize = 265.0;

  static const splashBackground = Color(0xFF210000);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: displaySize,
      height: displaySize,
      child: Image.asset(
        assetPath,
        width: displaySize,
        height: displaySize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        cacheWidth: displaySize.round(),
        cacheHeight: displaySize.round(),
      ),
    );
  }
}
