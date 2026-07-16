import 'dart:ui';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Jellyfin image URL caps for Android TV / leanback (1080p UI, low RAM).
///
/// Keep tight: OX images 302 to TMDB discrete tiers (w342/w500/w780). A 1280 fill
/// still lands on w780 and was OOM-killing home + movies on TCL leanback.
abstract final class OxplayerTvImageSizes {
  /// Grid posters, episode thumbs, person photos → TMDB w342-ish.
  static const Size primary = Size(280, 280);

  /// Detail hero / banner backdrops → prefer w500 over w780.
  static const Size backdrop = Size(640, 360);

  /// Title logos on detail screens.
  static const Size logo = Size(240, 240);

  static Size forImageType(ImageType type) {
    return switch (type) {
      ImageType.logo => logo,
      ImageType.backdrop => backdrop,
      _ => primary,
    };
  }

  static int clampDimension(int value, double cap) {
    final max = cap.round();
    return value > max ? max : value;
  }

  static (int width, int height) clampPair({
    required int maxWidth,
    required int maxHeight,
    required Size cap,
  }) {
    return (
      clampDimension(maxWidth, cap.width),
      clampDimension(maxHeight, cap.height),
    );
  }
}
