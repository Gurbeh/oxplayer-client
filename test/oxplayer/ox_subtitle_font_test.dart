import 'package:flutter/material.dart';
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

    test('default settings use white fill with thin black outline', () {
      expect(OxSubtitleFont.defaultSettings.color, equals(Colors.white));
      expect(OxSubtitleFont.defaultSettings.outlineSize, 1);
    });

    test('assForceStyle includes outline and Persian font name', () {
      final style = OxSubtitleFont.assForceStyle(
        OxSubtitleFont.defaultSettings,
        language: 'fa',
      );
      expect(style, contains('FontName=Vazirmatn'));
      expect(style, contains('Outline=1'));
      expect(style, contains('OutlineColour='));
    });
  });
}
