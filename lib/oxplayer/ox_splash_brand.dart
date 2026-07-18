import 'package:flutter/material.dart';

/// Temporary OX splash branding (flag of Iran instead of app logo).
class OxSplashBrand extends StatelessWidget {
  const OxSplashBrand({super.key});

  static const assetPath = 'assets/oxplayer/flags/flag_of_iran_round.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
  }
}
