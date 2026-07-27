import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_stream_http_auth.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';

/// Aligned block sizes — must match ox-stream `maxFSBRangeBuffer` / CF Worker SPAN.
const int oxStreamWarmupHeaderBytes = 1048576; // 1 MiB
const int oxStreamWarmupMidBlockBytes = 4194304; // 4 MiB

const _warmupDedupeTtl = Duration(minutes: 2);
final Map<String, DateTime> _warmedAt = {};

/// Prefetch MKV header + first aligned mid-block so MPV cold start hits warm CDN/origin.
///
/// Uses **closed** byte ranges only. Open-ended `bytes=N-` must reach ox-stream intact
/// (CF range-normalize Worker passes them through; warming with open end is useless).
Future<void> oxplayerWarmStreamUrl(String url) async {
  if (!OxplayerConfig.isEnabled || kIsWeb) return;
  if (!oxplayerIsOxStreamUrl(url)) return;

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;

  final dedupeKey = '${uri.host}${uri.path}';
  final last = _warmedAt[dedupeKey];
  if (last != null && DateTime.now().difference(last) < _warmupDedupeTtl) {
    return;
  }
  _warmedAt[dedupeKey] = DateTime.now();

  final authHeaders = _warmupHeaders(url);
  final sw = Stopwatch()..start();

  // Header blocks MPV cold start; await it. Mid-block is best-effort background.
  await _warmRange(
    uri: uri,
    authHeaders: authHeaders,
    label: 'header',
    range: 'bytes=0-${oxStreamWarmupHeaderBytes - 1}',
    sw: sw,
  );
  unawaited(_warmRange(
    uri: uri,
    authHeaders: authHeaders,
    label: 'mid_block',
    range: 'bytes=131072-${131072 + oxStreamWarmupMidBlockBytes - 1}',
    sw: sw,
  ));
}

Future<void> _warmRange({
  required Uri uri,
  required Map<String, String> authHeaders,
  required String label,
  required String range,
  required Stopwatch sw,
}) async {
  try {
    final response = await http
        .get(uri, headers: {...authHeaders, 'Range': range})
        .timeout(const Duration(seconds: 12));
    OxplayerStreamLog.event('stream_warmup', fields: {
      'probe': label,
      'range': range,
      'status': response.statusCode,
      'bodyBytes': response.bodyBytes.length,
      'host': uri.host,
      'elapsedMs': sw.elapsedMilliseconds,
    });
  } catch (e) {
    OxplayerStreamLog.event('stream_warmup', fields: {
      'probe': label,
      'range': range,
      'host': uri.host,
      'error': e.runtimeType.toString(),
      'elapsedMs': sw.elapsedMilliseconds,
    });
  }
}

Map<String, String> _warmupHeaders(String url) {
  final headers = Map<String, String>.from(OxplayerStreamHttpAuth.defaultStreamRequestHeaders());
  final bearer = OxplayerStreamHttpAuth.bearerFor(url);
  if (bearer != null && bearer.isNotEmpty) {
    headers['Authorization'] = 'Bearer $bearer';
  }
  return headers;
}
