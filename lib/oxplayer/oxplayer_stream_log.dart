import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Stream playback tracing — visible in `pnpm dev:android:logs --stream`.
///
/// Chopper only logs Jellyfin API (`api.oxplayer.*`). Video bytes go direct to
/// the device's own TDLib session and never hit the HTTP client interceptor.
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

}
