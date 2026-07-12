import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_tv_image_sizes.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/image_provider.dart';

/// Caps Jellyfin image fill dimensions on leanback TV to reduce decode RAM.
class OxplayerImageNotifier extends ImageNotifier {
  OxplayerImageNotifier({required super.ref});

  bool get _leanBack => ref.read(argumentsStateProvider).leanBackMode;

  @override
  String getItemsImageUrl(
    String? itemId, {
    ImageType type = ImageType.primary,
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = OxplayerTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: OxplayerTvImageSizes.forImageType(type),
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getItemsImageUrl(
      itemId,
      type: type,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }

  @override
  String getBackdropImage(
    String itemId,
    int index,
    String hash, {
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = OxplayerTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: OxplayerTvImageSizes.backdrop,
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getBackdropImage(
      itemId,
      index,
      hash,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }

  @override
  String getChapterUrl(
    String itemId,
    int index, {
    ImageType type = ImageType.primary,
    int maxHeight = 576,
    int maxWidth = 384,
    int quality = 90,
  }) {
    if (_leanBack) {
      final (w, h) = OxplayerTvImageSizes.clampPair(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        cap: OxplayerTvImageSizes.primary,
      );
      maxWidth = w;
      maxHeight = h;
    }
    return super.getChapterUrl(
      itemId,
      index,
      type: type,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      quality: quality,
    );
  }
}
