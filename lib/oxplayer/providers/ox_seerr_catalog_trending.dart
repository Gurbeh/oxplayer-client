import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

part 'ox_seerr_catalog_trending.g.dart';

@riverpod
class OxSeerrCatalogTrending extends _$OxSeerrCatalogTrending {
  @override
  Future<List<SeerrDashboardPosterModel>> build() async {
    if (!OxplayerEnv.isEnabled) return const [];
    if (ref.read(userProvider)?.seerrCredentials?.isConfigured != true) {
      return const [];
    }
    return _load();
  }

  Future<void> refresh() async {
    if (!OxplayerEnv.isEnabled) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<List<SeerrDashboardPosterModel>> _load() async {
    final api = ref.read(seerrApiProvider);
    return api.discoverCatalogTrending(take: 20);
  }
}
