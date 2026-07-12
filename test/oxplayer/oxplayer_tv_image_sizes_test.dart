import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_tv_image_sizes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clamps large backdrop request to TV cap', () {
    final (w, h) = OxplayerTvImageSizes.clampPair(
      maxWidth: 2000,
      maxHeight: 2000,
      cap: OxplayerTvImageSizes.backdrop,
    );
    expect(w, 1280);
    expect(h, 720);
  });

  test('leaves small poster request unchanged', () {
    final (w, h) = OxplayerTvImageSizes.clampPair(
      maxWidth: 300,
      maxHeight: 300,
      cap: OxplayerTvImageSizes.primary,
    );
    expect(w, 300);
    expect(h, 300);
  });

  test('maps logo type to logo cap', () {
    final cap = OxplayerTvImageSizes.forImageType(ImageType.logo);
    expect(cap, OxplayerTvImageSizes.logo);
  });
}
