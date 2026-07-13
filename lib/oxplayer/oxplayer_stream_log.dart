import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_route.dart';

/// Stream playback tracing — visible in `pnpm dev:android:logs --stream`.
///
/// Chopper only logs Jellyfin API (`api.oxplayer.*`). Video bytes go direct to
/// ox-stream / Iran vanity stream and never hit the HTTP client interceptor.
abstract final class OxplayerStreamLog {
  static const _logName = 'OX_STREAM';

  static void event(String phase, {Map<String, Object?> fields = const {}}) {
    if (!OxplayerConfig.isEnabled) return;
    final parts = <String>['phase=$phase'];
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      parts.add('${e.key}=$v');
    }
    final line = 'OX_STREAM ${parts.join(' ')}';
    developer.log(line, name: _logName);
    debugPrint(line);
  }

  /// Redacts JWT/token query params; keeps host + path for CDN debugging.
  static String describeUrl(String? url) {
    if (url == null || url.isEmpty) return '(empty)';
    final uri = Uri.tryParse(url);
    if (uri == null) return '(invalid)';
    final redacted = Map<String, String>.from(uri.queryParameters)
      ..remove('token')
      ..remove('api_key')
      ..remove('ApiKey');
    final q = redacted.isEmpty
        ? ''
        : '?${redacted.entries.map((e) => '${e.key}=…').join('&')}';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}$q';
  }

  static String? describeHost(String? url) {
    if (url == null || url.isEmpty) return null;
    return Uri.tryParse(url)?.host;
  }

  static String formatDuration(Duration? d) {
    if (d == null) return 'null';
    final sec = d.inSeconds;
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}m${s}s (${d.inMilliseconds}ms)';
  }

  static void routeContext() {
    event('route', fields: {
      'edge': OxplayerRoute.active.name,
      'api': OxplayerRoute.apiBaseUrl,
      'streamVanity': OxplayerRoute.streamBaseUrl,
    });
  }

  /// Fire-and-forget Range probes on the resolved playback URL (dev / profile only).
  static void probeRangeAsync(String url) {
    if (!kDebugMode || !OxplayerConfig.isEnabled) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // /v/* requires JWT in query — unauthenticated probe always 401; use /cdn-probe/range for CDN checks.
    if (uri.path.contains('/v/')) return;
    unawaited(_probeRange(url));
  }

  static Future<void> _probeRange(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;

    for (final spec in const [
      ('bytes=0-1023', 'range_start'),
      ('bytes=131072-', 'range_mid'),
    ]) {
      final label = spec.$2;
      final range = spec.$1;
      final sw = Stopwatch()..start();
      try {
        final response = await http
            .get(uri, headers: {'Range': range})
            .timeout(const Duration(seconds: 12));
        sw.stop();
        final bodyLen = response.bodyBytes.length;
        event('cdn_range_probe', fields: {
          'probe': label,
          'range': range,
          'status': response.statusCode,
          'contentRange': response.headers['content-range'] ?? response.headers['Content-Range'],
          'acceptRanges': response.headers['accept-ranges'] ?? response.headers['Accept-Ranges'],
          'bodyBytes': bodyLen,
          'host': uri.host,
          'elapsedMs': sw.elapsedMilliseconds,
        });
      } catch (e) {
        sw.stop();
        event('cdn_range_probe', fields: {
          'probe': label,
          'range': range,
          'host': uri.host,
          'error': e.runtimeType.toString(),
          'elapsedMs': sw.elapsedMilliseconds,
        });
      }
    }
  }
}
