import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/credentials_model.dart';

/// In-memory Jellyfin access token for image/cache HTTP that bypasses Chopper interceptors.
abstract final class OxplayerImageAuth {
  static String? _accessToken;

  static String? get accessToken => _accessToken;

  static void syncFromAccount(AccountModel? account) {
    final token = account?.credentials.token.trim() ?? '';
    _accessToken = token.isEmpty ? null : token;
  }

  static void syncFromCredentials(CredentialsModel? credentials) {
    final token = credentials?.token.trim() ?? '';
    _accessToken = token.isEmpty ? null : token;
  }

  static void clear() {
    _accessToken = null;
  }
}
