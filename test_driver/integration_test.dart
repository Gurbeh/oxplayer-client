// Standard integration_test driver entry point for `flutter drive`.
//
// `flutter drive` launches the app the same way `flutter run` does (vs. `flutter test`'s
// device-test runner), which matters here: media_kit's native Windows video pipeline
// (mpv.Player.open()) has been observed to hang indefinitely when the app is launched via
// `flutter test integration_test/...` on Windows, but works normally under `flutter run` /
// `flutter drive`. See scripts/e2e-playback.mjs.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
