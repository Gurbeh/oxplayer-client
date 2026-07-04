import 'package:flutter/material.dart';

import 'package:fladder/models/settings/subtitle_settings_model.dart';

/// Bundled Persian subtitle font (Google Fonts — Vazirmatn, OFL).
abstract final class OxSubtitleFont {
  static const family = 'Vazirmatn';

  /// Used by mpv/libass when a Persian or Arabic subtitle track is active.
  static const libassFontAsset = 'assets/fonts/vazirmatn/Vazirmatn-Regular.ttf';

  /// Jellyfin / ISO-639 language tags that should use a Persian/Arabic font.
  static const _persianOrArabicLanguageCodes = {
    'fa',
    'fas',
    'per',
    'pes',
    'fae',
    'ar',
    'ara',
    'arb',
    'urd',
    'ur',
    'ckb',
    'kur',
  };

  static bool isPersianOrArabicLanguage(String? language) {
    if (language == null || language.isEmpty || language == 'Unknown') return false;
    final normalized = language.trim().toLowerCase().replaceAll('_', '-');
    final primary = normalized.split('-').first;
    return _persianOrArabicLanguageCodes.contains(primary);
  }

  /// True when a meaningful share of letters are in the Arabic Unicode block.
  static bool textUsesArabicScript(String text) {
    var arabicLetters = 0;
    var latinLetters = 0;
    for (final codeUnit in text.runes) {
      if (_isArabicScriptRune(codeUnit)) {
        arabicLetters++;
      } else if (_isLatinLetterRune(codeUnit)) {
        latinLetters++;
      }
    }
    if (arabicLetters == 0) return false;
    return arabicLetters >= latinLetters;
  }

  static bool shouldUsePersianFont({String? language, required String text}) {
    if (isPersianOrArabicLanguage(language)) return true;
    return textUsesArabicScript(text);
  }

  static TextDirection textDirectionFor(String text) =>
      textUsesArabicScript(text) ? TextDirection.rtl : TextDirection.ltr;

  static TextStyle styleFor(SubtitleSettingsModel model, {required bool usePersianFont}) {
    if (!usePersianFont) return model.style;
    return model.style.copyWith(
      fontFamily: family,
      letterSpacing: 0,
      wordSpacing: 0,
    );
  }

  static TextStyle backgroundStyleFor(SubtitleSettingsModel model, {required bool usePersianFont}) {
    return styleFor(model, usePersianFont: usePersianFont).copyWith(
      shadows: model.backGroundStyle.shadows,
      foreground: model.backGroundStyle.foreground,
    );
  }

  static bool _isArabicScriptRune(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0x08A0 && rune <= 0x08FF) ||
      (rune >= 0xFB50 && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);

  static bool _isLatinLetterRune(int rune) =>
      (rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A);
}
