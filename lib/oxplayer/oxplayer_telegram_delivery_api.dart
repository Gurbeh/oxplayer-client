import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_image_auth.dart';
import 'package:fladder/oxplayer/oxplayer_reader_kind_interceptor.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_bridge_controller.dart';
import 'package:fladder/src/tdlib_bridge.g.dart';

/// Client for the backend's Telegram delivery endpoints (apps/api's
/// telegram_delivery_routes.go).
///
/// Videos are copied out of a base channel straight into a DM this device's session controls — the
/// user's own Telegram account, or their personal bot — and read back by message id. Only this
/// device can learn that id (private-chat ids are numbered per side, so the id `copyMessage` handed
/// the sending bot is a different number) and only it knows which of the backend's round-robin
/// senders actually delivered — hence [report]. Once reported, later plays of the same file are
/// answered from the delivery table with no Telegram copy at all.
///
/// [report] and [forget] are best-effort: failing to report costs one redundant copy next time,
/// never a broken playback, so callers fire and forget rather than blocking the player on it.
abstract final class OxplayerTelegramDeliveryApi {
  static final http.Client _client = http.Client();

  /// Remembers that the file identified by [locator] was successfully read at [messageId] inside
  /// [providerBotId]'s DM. The server re-derives which file that is from the locator itself —
  /// the one string this device actually verified against the real Telegram caption.
  static Future<void> report({
    required String locator,
    required int messageId,
    required int providerBotId,
  }) async {
    final base = OxplayerEnv.apiBaseUrl;
    final token = OxplayerImageAuth.accessToken;
    if (base == null || token == null || locator.isEmpty || messageId <= 0 || providerBotId <= 0) {
      return;
    }
    try {
      final response = await _client.post(
        Uri.parse('$base/me/telegram-delivery'),
        headers: await _headersWithReaderKind(token),
        body: jsonEncode({
          'locator': locator,
          'messageId': messageId,
          'providerBotId': providerBotId,
        }),
      );
      if (response.statusCode >= 400) {
        debugPrint('OXPLAY_TDLIB: delivery report rejected (${response.statusCode})');
      }
    } catch (e) {
      debugPrint('OXPLAY_TDLIB: delivery report failed: $e');
    }
  }

  /// Forgets the remembered id for [locator] — the `force` escape hatch, called when the id no
  /// longer reads (message deleted, chat cleared, caption no longer matching). The next
  /// PlaybackInfo then takes the copy path again.
  static Future<void> forget({required String locator}) async {
    final base = OxplayerEnv.apiBaseUrl;
    final token = OxplayerImageAuth.accessToken;
    if (base == null || token == null || locator.isEmpty) return;
    try {
      await _client.delete(
        Uri.parse('$base/me/telegram-delivery/${Uri.encodeComponent(locator)}'),
        headers: await _headersWithReaderKind(token),
      );
    } catch (e) {
      debugPrint('OXPLAY_TDLIB: delivery forget failed: $e');
    }
  }

  /// The delivery senders currently configured server-side. The client starts, mutes and archives
  /// each one so copies never land in the user's visible inbox — which is why this is fetched from
  /// the API rather than bundled in the build: ops can add or retire a sender without an app
  /// release. Ids and usernames only; tokens never leave the server.
  ///
  /// Returns an empty list on any failure. The caller treats that as "nothing to prepare" and
  /// carries on — playback still works, copies just arrive un-archived.
  static Future<List<OxTdlibProviderBot>> providerBots() async {
    final base = OxplayerEnv.apiBaseUrl;
    final token = OxplayerImageAuth.accessToken;
    if (base == null || token == null) {
      debugPrint('OXPLAY_TDLIB: provider-bots skipped — no access token');
      return const [];
    }
    try {
      final response = await _client.get(
        Uri.parse('$base/telegram/provider-bots'),
        headers: _headers(token),
      );
      if (response.statusCode >= 400) {
        debugPrint('OXPLAY_TDLIB: provider-bots rejected (${response.statusCode})');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final bots = decoded['bots'];
      if (bots is! List) return const [];
      final parsed = <OxTdlibProviderBot>[];
      for (final entry in bots) {
        if (entry is! Map) continue;
        final bot = _parseProviderBot(entry);
        if (bot != null) parsed.add(bot);
      }
      if (parsed.isEmpty && bots.isNotEmpty) {
        debugPrint('OXPLAY_TDLIB: provider-bots parse skipped ${bots.length} row(s)');
      }
      return parsed;
    } catch (e) {
      debugPrint('OXPLAY_TDLIB: provider-bots failed: $e');
      return const [];
    }
  }

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'MediaBrowser Token="$token"',
      };

  /// [_headers] plus [oxplayerReaderKindHeader] — report/forget must land under the kind THIS
  /// device actually read with, not whichever kind the backend defaults to for the account. See
  /// OxplayerReaderKindInterceptor's doc for why (multi-device accounts with both a session and a
  /// bot connected).
  static Future<Map<String, String>> _headersWithReaderKind(String token) async {
    final isBot = await OxplayerTdlibBridgeController.instance().isNativeSessionActuallyBot();
    return {
      ..._headers(token),
      oxplayerReaderKindHeader: isBot ? 'bot' : 'session',
    };
  }

  static OxTdlibProviderBot? _parseProviderBot(Map entry) {
    final id = _providerBotId(entry['id']);
    final username = entry['username'];
    if (id == null || id <= 0 || username is! String || username.isEmpty) {
      return null;
    }
    return OxTdlibProviderBot(id: id, username: username);
  }

  static int? _providerBotId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}
