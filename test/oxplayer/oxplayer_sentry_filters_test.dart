import 'package:fladder/oxplayer/oxplayer_sentry_filters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('drops Flutter LiveText lifecycle SIGABRT', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'SIGABRT',
          value: 'SIGABRT: Abort',
          stackTrace: SentryStackTrace(frames: [
            SentryStackFrame(
              symbol: 'LiveText.isLiveTextInputAvailable',
              fileName: 'live_text.dart',
            ),
            SentryStackFrame(
              symbol: 'ServicesBinding._handleLifecycleMessage',
              fileName: 'binding.dart',
            ),
          ]),
        ),
      ],
    );

    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops license ANR on sideloaded emulator', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(type: 'ApplicationNotResponding', value: 'ApplicationNotResponding: Background ANR'),
      ],
      contexts: Contexts(
        app: SentryApp(
          viewNames: ['com.pairip.licensecheck.LicenseActivity'],
          inForeground: false,
        ),
        operatingSystem: SentryOperatingSystem(build: 'sdk_phone_arm64-eng 12 SP2A test-keys'),
      ),
      tags: {'isSideLoaded': 'true'},
    );

    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops background Flutter surface teardown ANR', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'ApplicationNotResponding',
          value: 'ApplicationNotResponding: Background ANR',
          stackTrace: SentryStackTrace(frames: [
            SentryStackFrame(function: 'io.flutter.embedding.engine.FlutterJNI.nativeSurfaceDestroyed'),
            SentryStackFrame(function: 'android.view.SurfaceView.notifySurfaceDestroyed'),
          ]),
        ),
      ],
      contexts: Contexts(app: SentryApp(inForeground: false)),
    );

    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops DNS lookup failures', () {
    final event = SentryEvent(
      message: SentryMessage(
        'Flutter error: ClientException with SocketException: Failed host lookup: api.oxplayer.app',
      ),
    );
    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops connection abort and intl dateSymbols noise', () {
    expect(
      OxplayerSentryFilters.beforeSend(
        SentryEvent(message: SentryMessage('ClientException: Software caused connection abort')),
        Hint(),
      ),
      isNull,
    );
    expect(
      OxplayerSentryFilters.beforeSend(
        SentryEvent(
          message: SentryMessage(
            'Flutter error: ClientException with SocketException: Connection timed out (OS Error: Connection timed out, errno = 110)',
          ),
        ),
        Hint(),
      ),
      isNull,
    );
    expect(
      OxplayerSentryFilters.beforeSend(
        SentryEvent(
          message: SentryMessage(
            'Flutter error: RangeError (end): Invalid value: Only valid value is 0: -1',
          ),
        ),
        Hint(),
      ),
      isNull,
    );
  });

  test('drops ChannelCallbackRecord native noise', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: '_ChannelCallbackRecord.invoke',
          value: 'SIGABRT: Abort',
        ),
      ],
    );
    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops pigeon channel-error when native player is gone', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'PlatformException',
          value:
              'PlatformException(channel-error, Unable to establish connection on channel: "dev.flutter.pigeon.nl_jknaapen_fladder.settings.PlayerSettingsPigeon.sendPlayerSettings"., null, null)',
        ),
      ],
    );
    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops MissingPluginException on pigeon player channels', () {
    expect(
      OxplayerSentryFilters.shouldReportPlatformError(
        MissingPluginException(
          'No implementation found for method sendPlayerSettings on channel dev.flutter.pigeon.nl_jknaapen_fladder.settings.PlayerSettingsPigeon.sendPlayerSettings',
        ),
      ),
      isFalse,
    );
    expect(
      OxplayerSentryFilters.shouldReportPlatformError(
        MissingPluginException('No implementation found for method foo on channel some.other.channel'),
      ),
      isTrue,
    );
  });

  test('drops RenderFlex overflow layout noise', () {
    final event = SentryEvent(
      message: SentryMessage('Flutter error: A RenderFlex overflowed by 89 pixels on the bottom.'),
    );
    expect(OxplayerSentryFilters.beforeSend(event, Hint()), isNull);
  });

  test('drops window_manager MissingPluginException on Android', () {
    expect(
      OxplayerSentryFilters.shouldReportPlatformError(
        MissingPluginException('No implementation found for method isFullScreen on channel window_manager'),
      ),
      isFalse,
    );
  });

  test('drops media_kit NativeReferenceHolder cleanup PathNotFoundException', () {
    expect(
      OxplayerSentryFilters.shouldReportPersistedLog(
        'Flutter error: PathNotFoundException: Cannot retrieve length of file, path = '
        "'/data/user/0/app.oxplayer.dev/files/.com.alexmercerind.media_kit.NativeReferenceHolder.16947.src'",
      ),
      isFalse,
    );
  });

  test('drops handshake and volume anomaly telemetry', () {
    expect(
      OxplayerSentryFilters.shouldReportPersistedLog(
        'Flutter error: HandshakeException: Handshake error in client',
      ),
      isFalse,
    );
    expect(
      OxplayerSentryFilters.beforeSend(
        SentryEvent(message: SentryMessage('playback volume anomaly: volume_restored_on_play_event')),
        Hint(),
      ),
      isNull,
    );
  });
}
