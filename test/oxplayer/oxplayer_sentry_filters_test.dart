import 'package:fladder/oxplayer/oxplayer_sentry_filters.dart';
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
}
