import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

part 'ox_catalog_follow.g.dart';

Map<String, String> _oxAuthHeaders(Ref ref) {
  final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
  return {
    'Authorization': 'MediaBrowser Token="$token"',
    'Accept': 'application/json',
  };
}

@riverpod
class OxCatalogFollowStatus extends _$OxCatalogFollowStatus {
  @override
  Future<bool> build(String catalogId) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return false;
    final baseUrl = ref.read(serverUrlProvider);
    final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
    if (baseUrl == null || baseUrl.isEmpty || token.isEmpty) return false;

    final uri = Uri.parse('$baseUrl/me/follows/$catalogId');
    final response = await http.get(uri, headers: _oxAuthHeaders(ref));
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) return false;
    return body['following'] == true;
  }

  Future<void> setFollowing(bool following) async {
    if (!OxplayerEnv.isEnabled || catalogId.isEmpty) return;
    final baseUrl = ref.read(serverUrlProvider);
    final token = ref.read(userProvider)?.credentials.token.trim() ?? '';
    if (baseUrl == null || baseUrl.isEmpty || token.isEmpty) return;

    final uri = Uri.parse('$baseUrl/me/follows/$catalogId');
    final response = following
        ? await http.put(uri, headers: _oxAuthHeaders(ref))
        : await http.delete(uri, headers: _oxAuthHeaders(ref));
    if (response.statusCode == 200) {
      state = AsyncData(following);
    }
  }

  Future<void> toggle() async {
    final current = state.value ?? false;
    await setFollowing(!current);
  }
}
