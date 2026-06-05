import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:fladder/oxplayer/oxplayer_brand.dart';

/// Login header: brand icon + name. Uses the full-color SVG (no theme ShaderMask).
class OxplayerLoginLogo extends StatelessWidget {
  const OxplayerLoginLogo({super.key});

  static const double _iconSize = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'icons/oxplayer_icon.svg',
            width: _iconSize,
            height: _iconSize,
          ),
          const SizedBox(width: 16),
          Text(
            OxplayerBrand.appName,
            style: theme.textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }
}
