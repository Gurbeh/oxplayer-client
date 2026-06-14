import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Single-shot flag: next PlaybackInfo request includes X-OX-Force-Repair.
final oxplayerForceRepairNextPlaybackProvider = StateProvider<bool>((ref) => false);

const oxplayerForceRepairHeader = 'X-OX-Force-Repair';

/// Adds [oxplayerForceRepairHeader] on the next PlaybackInfo POST when the flag is set.
class OxplayerForceRepairInterceptor implements Interceptor {
  OxplayerForceRepairInterceptor(this.ref);

  final Ref ref;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final path = chain.request.url.path.toLowerCase();
    if (!path.contains('playbackinfo')) {
      return chain.proceed(chain.request);
    }

    final forceRepair = ref.read(oxplayerForceRepairNextPlaybackProvider);
    if (!forceRepair) {
      return chain.proceed(chain.request);
    }

    ref.read(oxplayerForceRepairNextPlaybackProvider.notifier).state = false;
    final headers = Map<String, String>.from(chain.request.headers);
    headers[oxplayerForceRepairHeader] = '1';
    return chain.proceed(chain.request.copyWith(headers: headers));
  }
}

void oxplayerArmForceRepairPlayback(Ref ref) {
  ref.read(oxplayerForceRepairNextPlaybackProvider.notifier).state = true;
}
