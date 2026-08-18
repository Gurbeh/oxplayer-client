import 'dart:ui';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Jellyfin image URL caps for Android TV / leanback (1080p UI, low RAM).
///
/// Phone slider asks fill 2000 (backdrop → original). TV heroes fetch original
/// and decode at 1080; grids stay 360 so ImageCache does not OOM.
abstract final class OxplayerTvImageSizes {
  /// Grid posters, episode thumbs, person photos → TMDB w342-ish.
  static const Size primary = Size(280, 280);

  /// Detail hero / home slider backdrops → TMDB original (fill 1920).
  static const Size backdrop = Size(1920, 1080);

  /// Title logos on detail screens.
  static const Size logo = Size(240, 240);

  /// Default FladderImage decodeHeight (520) and grids stay here on TV.
  static const int decodeGridHeight = 360;

  /// Home slider + detail hero. Callers must pass this as decodeHeight.
  static const int decodeHeroHeight = 1080;

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

  /// Grid/default decodeHeight stays 360. Explicit hero (>=1080) uses 1080.
  static int clampDecodeHeight(int decodeHeight) {
    if (decodeHeight >= decodeHeroHeight) {
      return decodeHeroHeight;
    }
    return decodeHeight > decodeGridHeight ? decodeGridHeight : decodeHeight;
  }
}
