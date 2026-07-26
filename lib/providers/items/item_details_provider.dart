import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/oxplayer/ox_library_item_ratings.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ItemDetailsFetchResult = ({
  ItemBaseModel? item,
  List<String> trace,
  int attempts,
  int? lastHttpStatus,
});

final itemDetailsProvider = StateNotifierProvider.autoDispose<ItemDetailsNotifier, ItemBaseModel?>((ref) {
  return ItemDetailsNotifier(ref);
});

class ItemDetailsNotifier extends StateNotifier<ItemBaseModel?> {
  ItemDetailsNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<ItemBaseModel?> fetchDetails(String itemId) async {
    return (await fetchDetailsWithTrace(itemId)).item;
  }

  Future<ItemDetailsFetchResult> fetchDetailsWithTrace(String itemId) async {
    final trace = <String>[];
    if (itemId.isEmpty) {
      trace.add('empty_item_id');
      return (item: null, trace: trace, attempts: 0, lastHttpStatus: null);
    }

    final attempts = OxplayerEnv.isEnabled ? 3 : 1;
    int? lastHttpStatus;
    for (var attempt = 0; attempt < attempts; attempt++) {
      trace.add('attempt_${attempt + 1}');
      if (OxplayerEnv.isEnabled) {
        if (attempt == 0) {
          final cached = await oxLoadCachedLibraryItemDetails(ref, itemId);
          if (cached != null) {
            trace.add('disk_cache_hit');
            return (item: cached.model, trace: trace, attempts: attempt + 1, lastHttpStatus: lastHttpStatus);
          }
          trace.add('disk_cache_miss');
        }

        final ox = await oxFetchLibraryItemDetails(ref, itemId);
        if (ox != null) {
          trace.add('ox_fetch_hit');
          return (item: ox.model, trace: trace, attempts: attempt + 1, lastHttpStatus: lastHttpStatus);
        }
        trace.add('ox_fetch_miss');
      }

      final response = await api.usersUserIdItemsItemIdGet(itemId: itemId);
      lastHttpStatus = response.statusCode;
      if (response.body != null) {
        trace.add('chopper_hit_${response.statusCode}');
        return (item: response.bodyOrThrow, trace: trace, attempts: attempt + 1, lastHttpStatus: lastHttpStatus);
      }
      trace.add('chopper_miss_${response.statusCode}');

      if (attempt + 1 < attempts) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
    return (item: null, trace: trace, attempts: attempts, lastHttpStatus: lastHttpStatus);
  }
}
