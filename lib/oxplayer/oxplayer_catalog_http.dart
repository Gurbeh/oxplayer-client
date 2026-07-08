import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/oxplayer/oxplayer_provider_read.dart';
import 'package:fladder/providers/user_provider.dart';

Map<String, String> oxCatalogApiHeaders(Ref ref) {
  final credentials = ref.read(userProvider)?.credentials;
  if (credentials == null || credentials.token.trim().isEmpty) {
    return const {};
  }
  return {
    ...oxplayerMediaBrowserHeaders(ref.read, credentials),
    'Accept': 'application/json',
  };
}
