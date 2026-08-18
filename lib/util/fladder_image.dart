import 'package:flutter/material.dart';

import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transparent_image/transparent_image.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_image_log.dart';
import 'package:fladder/oxplayer/oxplayer_tv_image_sizes.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';

class FladderImage extends ConsumerWidget {
  final ImageData? image;
  final Widget Function(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded)? frameBuilder;
  final Widget Function(BuildContext context, Object object, StackTrace? stack)? imageErrorBuilder;
  final Widget? placeHolder;
  final StackFit stackFit;
  final BoxFit fit;
  final BoxFit? blurFit;
  final AlignmentGeometry? alignment;
  final bool disableBlur;
  final bool blurOnly;
  final int decodeHeight;
  final bool cachedImage;
  const FladderImage({
    required this.image,
    this.frameBuilder,
    this.imageErrorBuilder,
    this.placeHolder,
    this.stackFit = StackFit.expand,
    this.fit = BoxFit.cover,
    this.blurFit,
    this.alignment,
    this.disableBlur = false,
    this.blurOnly = false,
    this.decodeHeight = 520,
    this.cachedImage = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leanBackMode = ref.watch(argumentsStateProvider.select((value) => value.leanBackMode));
    final useBluredPlaceHolder =
        !leanBackMode && ref.watch(clientSettingsProvider.select((value) => value.blurPlaceHolders));
    final newImage = image;
    final rawProvider = cachedImage ? image?.imageProvider : image?.nonCachedImageProvider;
    // OX TV: decodeHeight was unused — TMDB 302 returns full-tier bitmaps; ResizeImage
    // keeps Flutter ImageCache from holding w1280 RGBA on leanback grids. Heroes pass 720.
    ImageProvider? imageProvider = rawProvider;
    if (OxplayerConfig.isEnabled && leanBackMode && rawProvider != null) {
      final maxH = OxplayerTvImageSizes.clampDecodeHeight(decodeHeight);
      if (decodeHeight >= OxplayerTvImageSizes.decodeHeroHeight) {
        OxplayerImageLog.event('tv_hero_decode', fields: {
          'decodeHeight': maxH,
          'path': image?.path ?? '',
        });
      }
      imageProvider = ResizeImage(rawProvider, height: maxH);
    }

    if (newImage == null) {
      return placeHolder ?? Container();
    } else {
      return Stack(
        key: Key(newImage.key),
        fit: stackFit,
        children: [
          // flutter_blurhash requires length >= 6; empty/stub hashes from API must not decode.
          if ((!disableBlur && useBluredPlaceHolder && newImage.hash.length >= 6) ||
              (blurOnly && newImage.hash.length >= 6))
            Image(
              image: BlurHashImage(
                newImage.hash,
                decodingHeight: 16,
                decodingWidth: 16,
              ),
              fit: blurFit ?? fit,
              height: 16,
            ),
          if (!blurOnly && imageProvider != null)
            FadeInImage(
              placeholder: MemoryImage(kTransparentImage),
              fit: fit,
              placeholderFit: fit,
              alignment: alignment ?? Alignment.center,
              filterQuality: OxplayerConfig.isEnabled ? FilterQuality.medium : FilterQuality.low,
              imageErrorBuilder: imageErrorBuilder,
              image: imageProvider,
            )
        ],
      );
    }
  }
}
