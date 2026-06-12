import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/user_provider.dart';

/// Retry on each home mount until configured (covers VIP upgrades + transient 503).
void oxplayerMaybeConfigureSeerr(WidgetRef ref) {
  if (!OxplayerEnv.isEnabled) return;
  if (ref.read(userProvider)?.seerrCredentials?.isConfigured == true) return;
  unawaited(oxplayerConfigureSeerrFromServer(ref));
}

/// Server-driven Seerr credentials for VIP/admin (GET /me/seerr). No user types in the client.
Future<void> oxplayerConfigureSeerrFromServer(WidgetRef ref) async {
  if (!OxplayerEnv.isEnabled) return;

  final account = ref.read(userProvider);
  final token = account?.credentials.token.trim() ?? '';
  if (token.isEmpty) return;

  final base = OxplayerEnv.apiBaseUrl;
  if (base == null) return;

  try {
    final response = await http.get(
      Uri.parse('$base/me/seerr'),
      headers: {
        'Authorization': 'MediaBrowser Token="$token"',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 404) {
      ref.read(userProvider.notifier).logoutSeerr();
      return;
    }
    if (response.statusCode != 200) return;

    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return;
    if (body['enabled'] == false) {
      ref.read(userProvider.notifier).logoutSeerr();
      return;
    }

    final serverUrl = body['serverUrl']?.toString().trim() ?? '';
    final sessionCookie = body['sessionCookie']?.toString().trim() ?? '';
    if (serverUrl.isEmpty || sessionCookie.isEmpty) return;

    ref.read(userProvider.notifier).setSeerrServerUrl(serverUrl);
    ref.read(userProvider.notifier).setSeerrSessionCookie(sessionCookie);
    ref.read(userProvider.notifier).setSeerrApiKey('');
  } catch (_) {
    // Transient failure — [oxplayerMaybeConfigureSeerr] will retry on next home mount.
  }
}
