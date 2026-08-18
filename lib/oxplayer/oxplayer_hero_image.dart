import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';

/// TV ImageNotifier clamps Primary to 280×280. Slider/detail heroes must request 1920×1080.
ImageData? oxplayerHeroImage(ImageData? image) {
  if (!OxplayerConfig.isEnabled || image == null || image.path.isEmpty) {
    return image;
  }
  final uri = Uri.tryParse(image.path);
  if (uri == null || uri.queryParameters.isEmpty) {
    return image;
  }
  const w = '1920';
  const h = '1080';
  if (uri.queryParameters['fillWidth'] == w && uri.queryParameters['fillHeight'] == h) {
    return image;
  }
  final q = Map<String, String>.from(uri.queryParameters);
  q['fillWidth'] = w;
  q['fillHeight'] = h;
  return image.copyWith(
    path: uri.replace(queryParameters: q).toString(),
    key: '${image.key}_hero1920',
  );
}
