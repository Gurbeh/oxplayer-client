import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// Routes after sign-out or session revocation in OX builds.
List<PageRouteInfo> oxplayerSignOutRouteList() {
  if (!OxplayerConfig.isEnabled) {
    return [LoginRoute()];
  }
  return [const OxplayerLoginRoute()];
}

/// Navigate to add another Telegram account without removing saved profiles.
List<PageRouteInfo> oxplayerAddAccountRouteList() {
  return [const OxplayerLoginRoute()];
}

/// Whether the login screen should open on the account picker instead of Telegram.
bool oxplayerLoginShowsAccountGrid(Ref ref) {
  return ref.read(sharedUtilityProvider).getAccounts().isNotEmpty;
}
