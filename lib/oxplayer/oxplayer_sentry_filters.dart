import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Drops known-benign client errors so Sentry reflects actionable issues only.
abstract final class OxplayerSentryFilters {
  static SentryEvent? beforeSend(SentryEvent event, Hint hint) {
    final message = _eventText(event);
    if (message != null && _shouldDrop(message)) return null;
    if (_isBenignAnr(event)) return null;
    if (_isFlutterLiveTextLifecycleCrash(event)) return null;
    if (_isChannelCallbackNativeNoise(event)) return null;
    if (_isPigeonChannelUnavailable(event)) return null;

    final tags = event.tags ?? {};
    if (tags['transient'] == 'true') return null;
    if (tags['perf'] == 'slow_screen' || tags['perf'] == 'slow_splash') return null;
    if (message != null && message.contains('playback volume anomaly:')) return null;

    if (_stackContainsAny(event, const [
      'LiveText.isLiveTextInputAvailable',
      'LiveTextInputStatusNotifier',
      '_handleLifecycleMessage',
      '_ChannelCallbackRecord.invoke',
      'PlayerSettingsPigeon.sendPlayerSettings',
      'VideoPlayerApi.setSubtitleSettings',
    ])) {
      return null;
    }

    return event;
  }

  /// Drops cold-start transactions where Fladder loads home recents (one Items/Latest per library view).
  static SentryTransaction? beforeSendTransaction(SentryTransaction transaction, Hint hint) {
    if (_isHomeItemsLatestN1(transaction)) return null;
    return transaction;
  }

  static bool shouldReportFlutterError(Object exception) {
    return shouldReportPlatformError(exception);
  }

  /// Whether a platform/async error should be forwarded to Sentry.
  static bool shouldReportPlatformError(Object error) {
    if (error is MissingPluginException) {
      return !_isBenignMissingPlugin(error.toString());
    }
    if (error is PlatformException && error.code == 'channel-error') {
      return !_isDetachedPlayerChannelMessage(error.message ?? error.toString());
    }
    return shouldReportPersistedLog(error.toString());
  }

  static bool shouldReportPersistedLog(String message) {
    return !_shouldDrop(message);
  }

  static bool _shouldDrop(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('invalid statuscode: 404') &&
        (lower.contains('/images/logo') || lower.contains('/images/primary'))) {
      return true;
    }
    if (lower.contains('timeoutexception') && lower.contains('cachednetworkimageprovider')) {
      return true;
    }
    if (lower.contains('failed host lookup') || lower.contains('no address associated with hostname')) {
      return true;
    }
    if (lower.contains('software caused connection abort') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('connection timed out') ||
        lower.contains('socketexception')) {
      return true;
    }
    if (lower.contains('renderflex overflowed')) {
      return true;
    }
    if (lower.contains('rangeerror') &&
        lower.contains('invalid value') &&
        lower.contains('only valid value is 0: -1')) {
      return true;
    }
    if (lower.contains('channelcallbackrecord.invoke')) {
      return true;
    }
    if (lower.contains('item not in your library')) {
      return true;
    }
    if (lower.contains('404 not found')) {
      return true;
    }
    if (lower.contains('null check operator used on a null value')) {
      return true;
    }
    if (lower.contains('invalid statuscode: 401') && lower.contains('/seerr/proxy/avatarproxy')) {
      return true;
    }
    if (lower.contains('video playback failed: hydrate_timeout')) {
      return true;
    }
    if (_isPigeonChannelUnavailableMessage(lower)) {
      return true;
    }
    if (lower.contains('missingpluginexception') && _isDetachedPlayerChannelMessage(lower)) {
      return true;
    }
    if (lower.contains('missingpluginexception') && lower.contains('window_manager')) {
      return true;
    }
    if (lower.contains('pathnotfoundexception') &&
        lower.contains('nativereferenceholder')) {
      return true;
    }
    if (lower.contains('handshakeexception') || lower.contains('handshake error')) {
      return true;
    }

    return false;
  }

  /// Pigeon channel-error when the native player handler is torn down (app detach/background).
  static bool _isPigeonChannelUnavailable(SentryEvent event) {
    final parts = <String>[
      _eventText(event) ?? '',
      event.message?.formatted ?? '',
      for (final ex in event.exceptions ?? const []) ex.type ?? '',
      for (final ex in event.exceptions ?? const []) ex.value ?? '',
      for (final ex in event.exceptions ?? const []) ..._framesText(ex.stackTrace?.frames ?? const []),
    ];
    return _isDetachedPlayerChannelMessage(parts.join(' '));
  }

  static bool _isBenignMissingPlugin(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('window_manager')) return true;
    return _isDetachedPlayerChannelMessage(lower);
  }

  static bool _isDetachedPlayerChannelMessage(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('missingpluginexception')) {
      return _isPigeonPlayerChannelName(lower);
    }
    if (!lower.contains('channel-error')) {
      return false;
    }
    return _isPigeonPlayerChannelName(lower);
  }

  static bool _isPigeonChannelUnavailableMessage(String lower) {
    return _isDetachedPlayerChannelMessage(lower);
  }

  static bool _isPigeonPlayerChannelName(String lower) {
    return lower.contains('playersettingspigeon.sendplayersettings') ||
        lower.contains('videoplayerapi.setsubtitlesettings') ||
        lower.contains('nl_jknaapen_fladder.settings.playersettingspigeon') ||
        lower.contains('nl_jknaapen_fladder.video.videoplayerapi') ||
        lower.contains('player_settings_helper.g.dart') ||
        lower.contains('video_player_helper.g.dart');
  }

  /// Drops ANRs from Google Play license verification on sideloaded/emulator builds,
  /// and background Flutter surface teardown stalls (engine/native, not app logic).
  static bool _isBenignAnr(SentryEvent event) {
    final parts = <String>[
      _eventText(event) ?? '',
      event.message?.formatted ?? '',
      for (final ex in event.exceptions ?? const []) ex.value ?? '',
      for (final ex in event.exceptions ?? const []) ..._framesText(ex.stackTrace?.frames ?? const []),
    ];
    final text = parts.join(' ').toLowerCase();
    if (!text.contains('applicationnotresponding') && !text.contains(' anr')) {
      return false;
    }

    if (text.contains('pairip') ||
        text.contains('licenseactivity') ||
        text.contains('licensecheck')) {
      return true;
    }

    if (text.contains('nativesurfacedestroyed') ||
        text.contains('surfacedestroyed') && text.contains('flutterrenderer')) {
      final inForeground = event.contexts.app?.inForeground;
      if (inForeground == false) {
        return true;
      }
    }

    final viewNames = event.contexts.app?.viewNames ?? const <String>[];
    if (viewNames.any((v) => v.toLowerCase().contains('license'))) {
      return true;
    }

    if (event.tags?['isSideLoaded'] == 'true') {
      final osBuild = (event.contexts.operatingSystem?.build ?? '').toLowerCase();
      if (osBuild.contains('test-keys') ||
          osBuild.contains('sdk_phone') ||
          osBuild.contains('-eng ')) {
        return true;
      }
    }

    return false;
  }

  /// Flutter framework bug: LiveText platform channel invoked while handling lifecycle.
  static bool _isFlutterLiveTextLifecycleCrash(SentryEvent event) {
    final parts = <String>[
      _eventText(event) ?? '',
      for (final ex in event.exceptions ?? const []) ex.value ?? '',
      for (final ex in event.exceptions ?? const []) ..._framesText(ex.stackTrace?.frames ?? const []),
    ];
    final text = parts.join(' ').toLowerCase();
    if (!text.contains('sigabrt') && !text.contains('abort')) {
      return false;
    }
    return text.contains('livetext') ||
        text.contains('_handlelifecyclemessage') ||
        text.contains('channelcallbackrecord') ||
        (text.contains('channelcallbackrecord') && text.contains('dispatchplatformmessage'));
  }

  /// Native/Dart platform-channel noise (LiveText lifecycle, etc.).
  static bool _isChannelCallbackNativeNoise(SentryEvent event) {
    final parts = <String>[
      _eventText(event) ?? '',
      event.message?.formatted ?? '',
      for (final ex in event.exceptions ?? const []) ex.type ?? '',
      for (final ex in event.exceptions ?? const []) ex.value ?? '',
      for (final ex in event.exceptions ?? const []) ..._framesText(ex.stackTrace?.frames ?? const []),
    ];
    final text = parts.join(' ').toLowerCase();
    if (text.contains('channelcallbackrecord')) return true;
    if ((text.contains('sigabrt') || text.contains('abort')) &&
        text.contains('dispatchplatformmessage')) {
      return true;
    }
    return false;
  }

  static bool _isHomeItemsLatestN1(SentryTransaction transaction) {
    var latestCalls = 0;
    for (final span in transaction.spans) {
      final hay = [
        span.context.description,
        span.data['url'],
        span.data['http.url'],
      ].whereType<String>().join(' ').toLowerCase();
      if (hay.contains('/items/latest')) latestCalls++;
    }
    return latestCalls >= 2;
  }

  static bool _stackContainsAny(SentryEvent event, List<String> needles) {
    for (final ex in event.exceptions ?? const []) {
      for (final frame in ex.stackTrace?.frames ?? const []) {
        final hay = _frameText(frame).toLowerCase();
        for (final needle in needles) {
          if (hay.contains(needle.toLowerCase())) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static Iterable<String> _framesText(Iterable<SentryStackFrame> frames) sync* {
    for (final frame in frames) {
      yield _frameText(frame);
    }
  }

  static String _frameText(SentryStackFrame frame) {
    return [
      frame.symbol,
      frame.function,
      frame.package,
      frame.absPath,
      frame.fileName,
    ].whereType<String>().join(' ');
  }

  static String? _eventText(SentryEvent event) {
    final throwable = event.throwable;
    if (throwable != null) return throwable.toString();
    return event.message?.formatted;
  }
}
