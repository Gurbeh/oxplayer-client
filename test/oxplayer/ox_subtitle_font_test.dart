import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/oxplayer/playback/ox_subtitle_font.dart';

void main() {
  group('OxSubtitleFont', () {
    test('detects Persian language tags', () {
      expect(OxSubtitleFont.isPersianOrArabicLanguage('fa'), isTrue);
      expect(OxSubtitleFont.isPersianOrArabicLanguage('fas'), isTrue);
      expect(OxSubtitleFont.isPersianOrArabicLanguage('per'), isTrue);
      expect(OxSubtitleFont.isPersianOrArabicLanguage('en'), isFalse);
      expect(OxSubtitleFont.isPersianOrArabicLanguage('Unknown'), isFalse);
    });

    test('detects Arabic script in subtitle text', () {
      expect(OxSubtitleFont.textUsesArabicScript('سلام دنیا'), isTrue);
      expect(OxSubtitleFont.textUsesArabicScript('Hello world'), isFalse);
      expect(OxSubtitleFont.textUsesArabicScript('این یک Hello است'), isTrue);
    });

    test('prefers track language over script', () {
      expect(
        OxSubtitleFont.shouldUsePersianFont(language: 'fa', text: 'Hello'),
        isTrue,
      );
    });
  });
}
