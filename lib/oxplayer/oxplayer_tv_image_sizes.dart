import 'dart:ui';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Jellyfin image URL caps for Android TV / leanback (1080p UI, low RAM).
abstract final class OxplayerTvImageSizes {
  /// Grid posters, episode thumbs, person photos.
  static const Size primary = Size(400, 400);

  /// Detail hero / banner backdrops.
  static const Size backdrop = Size(1280, 720);

  /// Title logos on detail screens.
  static const Size logo = Size(320, 320);

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
