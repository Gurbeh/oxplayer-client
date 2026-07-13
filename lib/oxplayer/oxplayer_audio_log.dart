import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';

/// Audio / volume / track-selection tracing for Android playback debug.
///
/// Visible in `pnpm dev:android:logs --stream` (filter includes `OX_AUDIO`).
abstract final class OxplayerAudioLog {
  static const _logName = 'OX_AUDIO';

  static void event(String phase, {Map<String, Object?> fields = const {}}) {
    if (!OxplayerConfig.isEnabled) return;
    final parts = <String>['phase=$phase'];
    for (final e in fields.entries) {
      final v = e.value;
      if (v == null) continue;
      parts.add('${e.key}=$v');
    }
    final line = 'OX_AUDIO ${parts.join(' ')}';
    developer.log(line, name: _logName);
    debugPrint(line);
  }
}
