import 'package:flutter/material.dart';

/// Decode height for Jellyfin posters on Android TV / leanback.
///
/// Fladder caps decoded bitmaps at 520px on TV, but focused row posters on 1080p
/// need ~750–900px — upscaling causes blurry thumbnails.
int oxplayerTvImageDecodeHeight(BuildContext context, {required int fallback}) {
  final mq = MediaQuery.of(context);
  // Roughly matches [TVPosterRow] focused item height (~33% of logical screen).
  final estimatedPosterLogicalHeight = mq.size.height * 0.33;
  final pixels = (estimatedPosterLogicalHeight * mq.devicePixelRatio).ceil();
  return pixels.clamp(fallback, 1080);
}
