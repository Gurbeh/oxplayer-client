import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_hero_image.dart';
import 'package:fladder/oxplayer/oxplayer_image_log.dart';

/// Home slider is landscape; prefer backdrop over the 600px primary poster.
ImageData? oxplayerSliderImage(ItemBaseModel item) {
  if (!OxplayerConfig.isEnabled) {
    return item.bannerImage;
  }
  final image = oxplayerHeroImage(
    item.images?.backDrop?.firstOrNull ??
        item.getPosters?.backDrop?.firstOrNull ??
        item.bannerImage,
  );
  OxplayerImageLog.event('slider', fields: {
    'item': item.id,
    'path': image?.path ?? '(none)',
  });
  return image;
}
