import 'package:flutter/material.dart';

/// Temporary OX splash branding (flag of Iran instead of app logo).
class OxSplashBrand extends StatelessWidget {
  const OxSplashBrand({super.key});

  /// 512px PNG (~50KB). Do not use multi-MB source art — decodes into RAM on low-memory TVs.
  static const assetPath = 'assets/oxplayer/flags/iran_splash_512.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: 512,
    );
  }
}
