import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/oxplayer/playback/ox_persian_language.dart';

void main() {
  group('OxPersianLanguage', () {
    test('detects Persian language tags and names', () {
      expect(OxPersianLanguage.isPersianLanguage('fa'), isTrue);
      expect(OxPersianLanguage.isPersianLanguage('fas'), isTrue);
      expect(OxPersianLanguage.isPersianLanguage('Persian'), isTrue);
      expect(OxPersianLanguage.isPersianLanguage('Farsi'), isTrue);
      expect(OxPersianLanguage.isPersianLanguage('فارسی'), isTrue);
      expect(OxPersianLanguage.isPersianLanguage('en'), isFalse);
      expect(OxPersianLanguage.isPersianLanguage('ar'), isFalse);
    });

    test('showIranFlagForSubtitle respects off track', () {
      expect(
        OxPersianLanguage.showIranFlagForSubtitle(
          subtitleLanguage: 'fa',
          playbackModel: null,
          subtitleIndex: -1,
        ),
        isFalse,
      );
      expect(
        OxPersianLanguage.showIranFlagForSubtitle(
          subtitleLanguage: 'fa',
          playbackModel: null,
          subtitleIndex: 2,
        ),
        isTrue,
      );
    });
  });
}
