import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:fladder/models/settings/subtitle_settings_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/wrappers/players/base_player.dart';

/// Bundled Persian subtitle font (Vazirmatn v33.003, OFL).
abstract final class OxSubtitleFont {
  static const family = 'Vazirmatn';
  static const version = '33.003';

  /// Used by mpv/libass when a Persian or Arabic subtitle track is active.
  static const libassFontAsset = 'assets/fonts/vazirmatn/Vazirmatn-Regular.ttf';
  static const _libassBoldFontAsset = 'assets/fonts/vazirmatn/Vazirmatn-Bold.ttf';

  static String get libassFontForPlayer =>
      OxplayerConfig.isEnabled ? libassFontAsset : libassFallbackFont;

  static String? _cachedLibassFontsDir;
  static Future<String?>? _libassFontsDirFuture;

  /// Extract bundled Vazirmatn TTFs to a real filesystem dir for mpv/libass.
  ///
  /// media_kit only wires [PlayerConfiguration.libassAndroidFont] on Android.
  /// Desktop (Windows/macOS/Linux) burns subs via libass but never gets that
  /// asset path — without [sub-fonts-dir], `FontName=Vazirmatn` falls back.
  static Future<String?> ensureLibassFontsDir() {
    if (kIsWeb || !OxplayerConfig.isEnabled) {
      return Future<String?>.value(null);
    }
    if (_cachedLibassFontsDir != null) {
      return Future<String?>.value(_cachedLibassFontsDir);
    }
    return _libassFontsDirFuture ??= _extractLibassFontsDir();
  }

  static Future<String?> _extractLibassFontsDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(
        '${support.path}${Platform.pathSeparator}ox_libass_fonts'
        '${Platform.pathSeparator}$version',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _copyAssetIfNeeded(libassFontAsset, dir, 'Vazirmatn-Regular.ttf');
      await _copyAssetIfNeeded(_libassBoldFontAsset, dir, 'Vazirmatn-Bold.ttf');

      _cachedLibassFontsDir = dir.path;
      return dir.path;
    } catch (_) {
      _libassFontsDirFuture = null;
      return null;
    }
  }

  static Future<void> _copyAssetIfNeeded(
    String asset,
    Directory dir,
    String fileName,
  ) async {
    final out = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (await out.exists() && await out.length() > 0) return;
    final data = await rootBundle.load(asset);
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  /// OXPlayer default subtitle appearance (white fill + thin black outline).
  static const defaultSettings = SubtitleSettingsModel(
    color: Colors.white,
    outlineColor: Color.fromRGBO(0, 0, 0, 0.85),
    outlineSize: 1,
  );

  /// libass `sub-ass-force-style` string from user subtitle settings.
  static String assForceStyle(
    SubtitleSettingsModel settings, {
    String? language,
  }) {
    final parts = <String>[
      'PrimaryColour=${_assColor(settings.color)}',
      'OutlineColour=${_assColor(settings.outlineColor)}',
      'Outline=${settings.outlineSize.clamp(1, 25).round()}',
      'BorderStyle=1',
    ];
    if (shouldUsePersianFont(language: language, text: '')) {
      parts.insert(0, 'FontName=$family');
    }
    return parts.join(',');
  }

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

  static String _assColor(Color color) {
    final alpha = (255 - (color.a * 255).round()).clamp(0, 255);
    final red = (color.r * 255).round().clamp(0, 255);
    final green = (color.g * 255).round().clamp(0, 255);
    final blue = (color.b * 255).round().clamp(0, 255);
    return '&H${alpha.toRadixString(16).padLeft(2, '0')}'
        '${blue.toRadixString(16).padLeft(2, '0')}'
        '${green.toRadixString(16).padLeft(2, '0')}'
        '${red.toRadixString(16).padLeft(2, '0')}';
  }
}
