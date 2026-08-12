import 'dart:async';
import 'dart:developer';
import 'dart:math' show Random, min;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:square_progress_indicator/square_progress_indicator.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/album_model.dart';
import 'package:fladder/models/items/artist_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/photos_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/oxplayer/oxplayer_playback_prefetch.dart';
import 'package:fladder/oxplayer/oxplayer_native_playback.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/book_viewer_provider.dart';
import 'package:fladder/providers/items/book_details_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/book_viewer/book_viewer_screen.dart';
import 'package:fladder/screens/library_search/widgets/library_play_options_.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';

part 'play_playlist_helpers.dart';

/// List/detail play buttons dispose during async playback prep — keep root navigator context.
BuildContext _playbackRootContext(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).context;
}

/// Survives widget dispose while loading dialog / createPlaybackModel runs.
OxplayerRead _playbackRead(BuildContext context) {
  return ProviderScope.containerOf(context, listen: false).read;
}

extension BookBaseModelExtension on BookModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    if (kIsWeb) {
      FladderSnack.show(context.localized.unableToPlayBooksOnWeb, context: context);
      return;
    }
    if (this == null) {
      return;
    }
    var newProvider = provider;

    if (newProvider == null) {
      newProvider = bookDetailsProvider(this?.id ?? "");
      await ref.watch(bookDetailsProvider(this?.id ?? "").notifier).fetchDetails(this!);
    }

    ref.read(bookViewerProvider.notifier).fetchBook(this);
    await openBookViewer(
      context,
      newProvider,
      initialPage: currentPage ?? this?.currentPage,
    );
    parentContext?.refreshData();
    if (context.mounted) {
      await context.refreshData();
    }
  }
}

extension PhotoAlbumExtension on PhotoAlbumModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    final albumModel = this;
    if (albumModel == null) return;

    final api = ref.read(jellyApiProvider);
    final op = CancelableOperation.fromFuture(api.itemsGet(
        parentId: albumModel.id,
        includeItemTypes: FladderItemType.galleryItem.map((e) => e.dtoKind).toList(),
        recursive: true));

    _showLoadingIndicator(context, albumModel, op);

    final getChildItems = await op.valueOrCancellation(null);
    if (op.isCanceled || getChildItems == null) {
      if (!op.isCanceled) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (e) {
          log('Error closing loading dialog: $e');
        }
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final photos = getChildItems.body?.items.whereType<PhotoModel>() ?? [];

    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      log('Error closing loading dialog: $e');
    }

    if (photos.isEmpty) {
      return;
    }

    await context.pushRoute(PhotoViewerRoute(
      items: photos.toList(),
    ));

    if (context.mounted) {
      await context.refreshData();
    }
    return;
  }
}

extension ChannelModelExtension on ChannelModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    if (this == null) return;
    final playContext = _playbackRootContext(context);
    final read = _playbackRead(playContext);

    await read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(read(playbackModelHelper).createPlaybackModel(
          playContext,
          this,
          forcedPlaybackType: PlaybackType.tv,
          showPlaybackOptions: false,
          startPosition: Duration.zero,
        ));

    _showLoadingIndicator(playContext, this!, op);

    final model = await op.valueOrCancellation(null);

    if (op.isCanceled || model == null) {
      if (!op.isCanceled) {
        _dismissPlaybackLoadingDialog(playContext);
        FladderSnack.show(playContext.localized.unableToPlayMedia, context: playContext);
      }
      return;
    }

    if (model is! TvPlaybackModel) {
      return;
    }

    await _playVideo(
      playContext,
      startPosition: Duration.zero,
      current: model.copyWith(
        channel: this,
      ),
      read: read,
      cancelOperation: op,
    );
  }
}

extension AlbumModelAudioPlayback on AlbumModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final album = this;
    if (album == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = await _fetchAlbumQueue(album, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          queue.first,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension AudioModelAudioPlayback on AudioModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final audio = this;
    if (audio == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = await _fetchAudioTrackQueue(audio, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final currentIndex = queue.indexWhere((element) => element.id == audio.id).clamp(0, queue.length - 1);
    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          audio,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension ArtistModelLatestTracksPlayback on ArtistModel? {
  Future<void> playLatestTracks(
    BuildContext context,
    WidgetRef ref, {
    AudioModel? startTrack,
    Duration? startPosition,
    bool showPlaybackOption = false,
    bool? shuffleEnabled,
  }) async {
    final artist = this;
    if (artist == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    if (shuffleEnabled != null) {
      ref.read(mediaPlaybackProvider.notifier).update((s) => s.copyWith(shuffleEnabled: shuffleEnabled));
    }

    final queueSource = ArtistCatalogQueueSource(artistId: artist.id, limit: 300);
    final queue = await queueSource.fetchQueue(ref.read);

    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final selectedItem = startTrack != null
        ? queue.firstWhereOrNull((element) => element.id == startTrack.id) ?? queue.first
        : (shuffleEnabled == true && queue.length > 1)
            ? queue[Random().nextInt(queue.length)]
            : queue.first;
    final currentIndex = queue.indexWhere((element) => element.id == selectedItem.id).clamp(0, queue.length - 1);

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          selectedItem,
          libraryQueue: queue,
          queueSource: queueSource,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension AudioModelListPlayback on List<AudioModel> {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = cast<ItemBaseModel>().toList();

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          queue.first,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          0,
          actualStartPosition,
        );
  }
}

extension AlbumModelInstantMixPlayback on AlbumModel? {
  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final album = this;
    if (album == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: AlbumInstantMixQueueSource(albumId: album.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }
}

extension ArtistModelInstantMixPlayback on ArtistModel? {
  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final artist = this;
    if (artist == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: ArtistInstantMixQueueSource(artistId: artist.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }
}

extension AudioModelInstantMixPlayback on AudioModel? {
  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final audio = this;
    if (audio == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: AudioInstantMixQueueSource(audioId: audio.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }
}

extension AlbumModelAddToQueue on AlbumModel? {
  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final album = this;
    if (album == null) return;

    final queue = await _fetchAlbumQueue(album, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue(queue);
    if (context.mounted) {
      FladderSnack.show(context.localized.addedToQueue(queue.length), context: context);
    }
  }
}

extension AudioModelAddToQueue on AudioModel? {
  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final audio = this;
    if (audio == null) return;

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue([audio]);
    FladderSnack.show(context.localized.addedToQueue(1), context: context);
  }
}

extension ArtistModelAddToQueue on ArtistModel? {
  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final artist = this;
    if (artist == null) return;

    final queueSource = ArtistCatalogQueueSource(artistId: artist.id, limit: 300);
    final queue = await queueSource.fetchQueue(ref.read);

    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue(queue);
    if (context.mounted) {
      FladderSnack.show(context.localized.addedToQueue(queue.length), context: context);
    }
  }
}

Future<List<ItemBaseModel>> _fetchAlbumQueue(AlbumModel album, WidgetRef ref) async {
  final response = await ref.read(jellyApiProvider).itemsGet(
        parentId: album.id,
        includeItemTypes: [BaseItemKind.audio],
        enableUserData: true,
        enableImages: true,
        imageTypeLimit: 1,
        fields: [ItemFields.primaryimageaspectratio, ItemFields.mediasources, ItemFields.mediastreams],
        sortBy: [ItemSortBy.sortname],
        sortOrder: [SortOrder.ascending],
        limit: 200,
      );

  final tracks = response.body?.items.whereType<AudioModel>().toList() ?? [];
  tracks.sort((a, b) {
    final aIndex = a.trackNumber ?? 0;
    final bIndex = b.trackNumber ?? 0;
    return aIndex.compareTo(bIndex);
  });
  return tracks;
}

Future<List<ItemBaseModel>> _fetchAudioTrackQueue(AudioModel audio, WidgetRef ref) async {
  final albumId = audio.albumId ?? audio.parentId;
  if (albumId == null || albumId.isEmpty) {
    return [audio];
  }

  final response = await ref.read(jellyApiProvider).itemsGet(
        parentId: albumId,
        includeItemTypes: [BaseItemKind.audio],
        enableUserData: true,
        enableImages: true,
        imageTypeLimit: 1,
        fields: [ItemFields.primaryimageaspectratio, ItemFields.mediasources, ItemFields.mediastreams],
        sortBy: [ItemSortBy.sortname],
        sortOrder: [SortOrder.ascending],
        limit: 200,
      );

  final tracks = response.body?.items.whereType<AudioModel>().toList() ?? [];
  tracks.sort((a, b) {
    final aIndex = a.trackNumber ?? 0;
    final bIndex = b.trackNumber ?? 0;
    return aIndex.compareTo(bIndex);
  });

  if (tracks.isEmpty) {
    return [audio];
  }
  return tracks;
}

Future<void> _playInstantMix(
  BuildContext context,
  WidgetRef ref, {
  required PlaybackQueueSource queueSource,
  Duration? startPosition,
  bool showPlaybackOption = false,
}) async {
  await ref.read(videoPlayerProvider.notifier).init();

  final queue = await queueSource.fetchQueue(ref.read);
  if (queue.isEmpty) {
    FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    return;
  }

  final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
        context,
        queue.first,
        libraryQueue: queue,
        queueSource: queueSource,
        showPlaybackOptions: showPlaybackOption,
        startPosition: startPosition,
      ));

  final model = await op.valueOrCancellation(null);
  if (op.isCanceled || model == null) {
    if (!op.isCanceled && !showPlaybackOption) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    }
    return;
  }

  final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
  final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

  await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
        model,
        queue,
        currentIndex,
        actualStartPosition,
      );
}

extension ItemBaseModelExtensions on ItemBaseModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async =>
      switch (this) {
        PhotoAlbumModel album => album.play(context, ref),
        AlbumModel album => album.play(context, ref),
        AudioModel audio => audio.play(context, ref),
        PlaylistModel playlist => playlist.play(
            context,
            ref,
            startPosition: startPosition,
            showPlaybackOption: showPlaybackOption,
          ),
        BookModel book => book.play(context, ref),
        ChannelModel channel => channel.play(context, ref),
        _ => _default(context, this, ref, startPosition: startPosition, showPlaybackOption: showPlaybackOption),
      };

  Future<void> _default(
    BuildContext context,
    ItemBaseModel? itemModel,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    if (itemModel == null) return;
    final playContext = _playbackRootContext(context);
    final read = _playbackRead(playContext);

    if (OxplayerEnv.isEnabled) {
      OxplayerPlaybackPrefetch.scheduleForItem(
        read,
        itemModel.id,
        startPosition: startPosition,
        mediaSourceId: itemModel.streamModel?.currentVersionStream?.id,
      );
    }

    final op = CancelableOperation.fromFuture((() async {
      // OX: defer MPV init to loadPlaybackItem — early init races provider bootstrap init().
      if (!OxplayerEnv.isEnabled) {
        await read(videoPlayerProvider.notifier).init();
      }
      return await read(playbackModelHelper).createPlaybackModel(
            playContext,
            itemModel,
            showPlaybackOptions: showPlaybackOption,
            startPosition: startPosition,
          );
    })());

    _showLoadingIndicator(playContext, itemModel, op);

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled) {
        unawaited(OxplayerPlaybackTelemetry.reportFailure(
          stage: 'playback_model',
          reason: 'unable_to_create_playback_model',
          itemId: itemModel.id,
        ));
        _dismissPlaybackLoadingDialog(playContext);
        if (!showPlaybackOption) {
          FladderSnack.show(playContext.localized.unableToPlayMedia, context: playContext);
        }
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    if (OxplayerEnv.isEnabled) {
      OxplayerStreamLog.event('playback_model_ready', fields: {
        'itemId': model.item.id,
        'hasMedia': model.media != null,
      });
    }

    await _playVideo(playContext, startPosition: actualStartPosition, current: model, read: read, cancelOperation: op);
  }
}

extension ItemBaseModelsBooleans on List<ItemBaseModel> {
  Future<void> playLibraryItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (isEmpty) return;
    final playContext = _playbackRootContext(context);
    final read = _playbackRead(playContext);

    await read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(Future(() async {
      List<List<ItemBaseModel>> newList = await Future.wait(map((element) async {
        switch (element.type) {
          case FladderItemType.series:
            return await read(jellyApiProvider).fetchEpisodeFromShow(seriesId: element.id);
          default:
            return [element];
        }
      }));

      var expandedList =
          newList.expand((element) => element).toList().where((element) => element.playAble).toList().uniqueBy(
                (value) => value.id,
              );

      if (shuffle) {
        expandedList.shuffle();
      }

      PlaybackModel? model = await read(playbackModelHelper).createPlaybackModel(
            playContext,
            expandedList.firstOrNull,
            libraryQueue: expandedList,
          );

      return (model, expandedList);
    }));

    _showLoadingIndicator(playContext, null, op);

    final result = await op.valueOrCancellation(null);
    if (op.isCanceled || result == null) {
      if (!op.isCanceled) {
        unawaited(OxplayerPlaybackTelemetry.reportFailure(
          stage: 'playback_model',
          reason: 'unable_to_create_playback_model',
          itemId: isNotEmpty ? first.id : null,
        ));
        _dismissPlaybackLoadingDialog(playContext);
        FladderSnack.show(playContext.localized.unableToPlayMedia, context: playContext);
      }
      return;
    }

    final PlaybackModel? model = result.$1;
    final List<ItemBaseModel> expandedList = result.$2;

    await _playVideo(playContext, read: read, queue: expandedList, current: model, cancelOperation: op);
    if (playContext.mounted) {
      RefreshState.maybeOf(playContext)?.refresh();
    }
  }

  Future<void> playMusicItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(Future(() async {
      final newList = await Future.wait(map((element) async {
        switch (element) {
          case AudioModel audio:
            return <ItemBaseModel>[audio];
          case AlbumModel album:
            return await _fetchAlbumQueue(album, ref);
          case ArtistModel artist:
            return await ArtistCatalogQueueSource(artistId: artist.id, limit: 300).fetchQueue(ref.read);
          default:
            return const <ItemBaseModel>[];
        }
      }));

      final expandedList =
          newList.expand((element) => element).whereType<AudioModel>().cast<ItemBaseModel>().toList().uniqueBy(
                (value) => value.id,
              );

      if (shuffle) {
        expandedList.shuffle();
      }

      final model = await ref.read(playbackModelHelper).createPlaybackModel(
            context,
            expandedList.firstOrNull,
            libraryQueue: expandedList,
          );

      return (model, expandedList);
    }));

    _showLoadingIndicator(context, null, op);

    final result = await op.valueOrCancellation(null);
    if (op.isCanceled || result == null) {
      if (!op.isCanceled) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (e) {
          log('Error closing loading dialog: $e');
        }
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final PlaybackModel? model = result.$1;
    final List<ItemBaseModel> expandedList = result.$2;

    if (model == null || expandedList.isEmpty) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final currentIndex =
        expandedList.indexWhere((element) => element.id == model.item.id).clamp(0, expandedList.length - 1);
    final actualStartPosition = await model.startDuration() ?? Duration.zero;

    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {}

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          expandedList,
          currentIndex,
          actualStartPosition,
        );

    if (context.mounted) {
      RefreshState.maybeOf(context)?.refresh();
    }
  }
}

void _dismissPlaybackLoadingDialog(BuildContext context) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator?.canPop() ?? false) {
    try {
      navigator!.pop();
    } catch (_) {}
  }
}

Future<void> _showLoadingIndicator(BuildContext context, ItemBaseModel? item, CancelableOperation op) async {
  return showDialog(
    barrierDismissible: false,
    useRootNavigator: true,
    context: context,
    builder: (context) => _LoadIndicatorCancelable(op: op, item: item),
  );
}

class _LoadIndicatorCancelable extends StatefulWidget {
  final ItemBaseModel? item;
  final CancelableOperation op;
  const _LoadIndicatorCancelable({required this.op, this.item});

  @override
  State<_LoadIndicatorCancelable> createState() => _LoadIndicatorCancelableState();
}

class _LoadIndicatorCancelableState extends State<_LoadIndicatorCancelable> {
  bool _showColdStartHint = false;
  Timer? _coldStartHintTimer;

  @override
  void initState() {
    super.initState();
    if (OxplayerEnv.isEnabled) {
      _coldStartHintTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showColdStartHint = true);
      });
    }
  }

  @override
  void dispose() {
    _coldStartHintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final op = widget.op;
    final radius = const BorderRadius.all(Radius.circular(4));

    return Dialog(
      constraints: const BoxConstraints(
        maxWidth: 450,
        maxHeight: 500,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: 16,
          children: [
            Expanded(
              child: Row(
                spacing: 16,
                children: [
                  if (item != null)
                    Flexible(
                      child: Container(
                        decoration: FladderTheme.defaultPosterDecoration,
                        clipBehavior: Clip.hardEdge,
                        height: 175,
                        child: AspectRatio(
                          aspectRatio: 0.7,
                          child: SquareProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                            strokeCap: StrokeCap.round,
                            strokeWidth: 8,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                ),
                                foregroundDecoration: BoxDecoration(
                                  borderRadius: radius,
                                  border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: FladderImage(
                                  image: item.getPosters?.primary,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SquareProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Text(
                          OxplayerEnv.isEnabled
                              ? context.localized.oxplayerPreparingPlayback
                              : context.localized.loading,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (item != null) ...[
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (_showColdStartHint && OxplayerEnv.isEnabled)
                          Text(
                            context.localized.oxplayerPlaybackColdStartHint,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad)
              IconButton(
                tooltip: context.localized.close,
                onPressed: () {
                  try {
                    op.cancel();
                  } catch (_) {}
                  Navigator.of(context, rootNavigator: true).pop();
                },
                icon: const Icon(IconsaxPlusLinear.close_square),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _playVideo(
  BuildContext context, {
  required PlaybackModel? current,
  Duration? startPosition,
  List<ItemBaseModel>? queue,
  required OxplayerRead read,
  VoidCallback? onPlayerExit,
  CancelableOperation? cancelOperation,
}) async {
  final playContext = context.mounted ? context : _playbackRootContext(context);

  if (current == null) {
    if (playContext.mounted) {
      unawaited(OxplayerPlaybackTelemetry.reportFailure(
        stage: 'playback_model',
        reason: 'playback_model_null',
      ));
      _dismissPlaybackLoadingDialog(playContext);
      FladderSnack.show(playContext.localized.unableToPlayMedia, context: playContext);
    }
    return;
  }

  if (cancelOperation?.isCanceled ?? false) return;

  final actualStartPosition = startPosition ?? await current.startDuration() ?? Duration.zero;
  if (!playContext.mounted) {
    if (OxplayerEnv.isEnabled) {
      OxplayerStreamLog.event('play_video_aborted', fields: {
        'reason': 'context_unmounted',
        'itemId': current.item.id,
      });
    }
    _dismissPlaybackLoadingDialog(playContext);
    return;
  }

  if (OxplayerEnv.isEnabled) {
    OxplayerStreamLog.event('play_video_start', fields: {
      'itemId': current.item.id,
      'startMs': actualStartPosition.inMilliseconds,
    });
  }

  final nativeOpenedEarly =
      OxplayerEnv.isEnabled && playContext.mounted && await oxplayerOpenNativePlayerEarly(read, playContext);
  if (!playContext.mounted) {
    if (OxplayerEnv.isEnabled) {
      OxplayerStreamLog.event('play_video_aborted', fields: {
        'reason': 'context_unmounted_after_native_early',
        'itemId': current.item.id,
      });
    }
    _dismissPlaybackLoadingDialog(playContext);
    return;
  }

  var loadedCorrectly = await read(videoPlayerProvider.notifier).loadPlaybackItem(
        current,
        actualStartPosition,
      );

  Timer? stuckWatch;
  if (loadedCorrectly && OxplayerEnv.isEnabled) {
    stuckWatch = oxplayerScheduleStuckPlaybackWatch(
      read: read,
      itemId: current.item.id,
      streamUrl: current.media?.url,
      catalogDuration: current.item.overview.runTime,
      startPosition: actualStartPosition,
    );
  }

  if (!loadedCorrectly && OxplayerEnv.isEnabled) {
    loadedCorrectly = await oxplayerMaybeRetryPlayAfterLoadFailure(
      read: read,
      current: current,
      startPosition: actualStartPosition,
    );
  }

  if (!loadedCorrectly) {
    stuckWatch?.cancel();
    if (playContext.mounted) {
      unawaited(OxplayerPlaybackTelemetry.reportFailure(
        stage: 'player_load',
        reason: 'load_playback_item_failed',
        itemId: current.item.id,
        streamUrl: current.media?.url,
      ));
      _dismissPlaybackLoadingDialog(playContext);
      FladderSnack.show(playContext.localized.errorOpeningMedia, context: playContext);
    }
    return;
  }

  if (cancelOperation?.isCanceled ?? false) {
    stuckWatch?.cancel();
    return;
  }

  _dismissPlaybackLoadingDialog(playContext);

  if (cancelOperation?.isCanceled ?? false) {
    stuckWatch?.cancel();
    return;
  }

  if (!nativeOpenedEarly) {
    await read(videoPlayerProvider.notifier).openPlayer(playContext);
  }
  if (playContext.mounted && AdaptiveLayout.of(playContext).isDesktop && defaultTargetPlatform != TargetPlatform.macOS) {
    await fullScreenHelper.closeFullScreenRead(read);
  }

  if (playContext.mounted) {
    if (cancelOperation?.isCanceled ?? false) return;
    await playContext.refreshData();
  }

  onPlayerExit?.call();
  stuckWatch?.cancel();
}
