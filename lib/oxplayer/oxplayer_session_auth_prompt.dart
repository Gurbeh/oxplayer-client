import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_image_auth.dart';
import 'package:fladder/oxplayer/oxplayer_navigation.dart';
import 'package:fladder/oxplayer/oxplayer_session_store.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/shared_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';

/// Set from [BaseAppWrapper] so auth prompts can navigate to login.
final oxplayerSessionRouterProvider = StateProvider<StackRouter?>((ref) => null);

bool _authPromptVisible = false;

/// Shows a persistent snack when the server rejects the session (401 after refresh).
/// User can tap Log out to clear credentials and return to login.
void oxplayerPromptReLogin(Ref ref) {
  if (_authPromptVisible) return;
  if (ref.read(userProvider) == null) return;

  final loc = ref.read(localizationContextProvider)?.localized;
  final message = loc?.oxplayerSessionExpiredMessage ??
      'Your session expired. Log out and sign in again.';
  final action = loc?.logout ?? 'Log out';

  _authPromptVisible = true;
  FladderSnack.show(
    message,
    permanent: true,
    actionLabel: action,
    onActionPressed: () => oxplayerPerformSignOut(ref),
    showCloseButton: true,
  );
}

void oxplayerResetAuthPrompt() {
  _authPromptVisible = false;
}

/// Clears OX session state and routes to the login screen.
Future<void> oxplayerPerformSignOut(Ref ref) async {
  oxplayerResetAuthPrompt();
  final account = ref.read(userProvider);
  final router = ref.read(oxplayerSessionRouterProvider);

  if (account != null) {
    await OxplayerSessionStore(ref.read(sharedPreferencesProvider)).clear(account);
  }
  OxplayerImageAuth.clear();

  await ref.read(authProvider.notifier).logOutUser();

  if (router != null) {
    await router.replaceAll(oxplayerSignOutRouteList(ref));
  }
  await ref.read(authProvider.notifier).initModel();
}
