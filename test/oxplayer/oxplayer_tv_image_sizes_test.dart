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
    expect(w, 640);
    expect(h, 360);
  });

  test('clamps poster request above TV primary cap', () {
    final (w, h) = OxplayerTvImageSizes.clampPair(
      maxWidth: 300,
      maxHeight: 300,
      cap: OxplayerTvImageSizes.primary,
    );
    expect(w, 280);
    expect(h, 280);
  });

  test('leaves small poster request unchanged', () {
    final (w, h) = OxplayerTvImageSizes.clampPair(
      maxWidth: 200,
      maxHeight: 200,
      cap: OxplayerTvImageSizes.primary,
    );
    expect(w, 200);
    expect(h, 200);
  });

  test('maps logo type to logo cap', () {
    final cap = OxplayerTvImageSizes.forImageType(ImageType.logo);
    expect(cap, OxplayerTvImageSizes.logo);
  });
}
