import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_media_variant.dart';

const _knownSourceTokens = {
  'web-dl',
  'webdl',
  'webrip',
  'bluray',
  'blu-ray',
  'hdtv',
  'remux',
};

/// Localized file/version label: `1080p - English - BluRay`, `1080p - dubbed (Persian) - WEB-DL`.
String oxplayerLocalizedVersionStreamLabel(AppLocalizations l10n, VersionStreamModel stream) {
  final meta = oxClassifyVersionStream(stream);
  final resolution = _resolutionLabel(meta, stream);
  final source = _sourceLabel(stream);
  final language = _localizedLanguageName(l10n, _primaryLanguage(stream));
  final middle = _middleLabel(l10n, meta.delivery, language);
  final parts = [resolution, middle, source].where((part) => part.isNotEmpty);
  return parts.join(' - ');
}

String oxplayerVersionStreamLabel(
  VersionStreamModel stream, {
  AppLocalizations? l10n,
}) {
  final serverName = stream.name.trim();
  if (OxplayerConfig.isEnabled && serverName.isNotEmpty) {
    if (l10n != null) {
      return _localizeServerVariantLabel(l10n, serverName);
    }
    return serverName;
  }
  if (OxplayerConfig.isEnabled && l10n != null) {
    final localized = oxplayerLocalizedVersionStreamLabel(l10n, stream);
    if (localized.isNotEmpty) {
      return localized;
    }
  }
  if (serverName.isNotEmpty) {
    return serverName;
  }
  final resolution = stream.detailedResolutionLabel.trim();
  if (resolution.isNotEmpty && resolution != 'Unknown Unknown') {
    return resolution;
  }
  final id = stream.id?.trim();
  if (id != null && id.isNotEmpty) {
    return id.replaceFirst(RegExp(r'^ms_'), 'Variant ');
  }
  return 'Variant ${stream.index + 1}';
}

/// Localize delivery/language tokens in a server-built label; keep technical segments intact.
String _localizeServerVariantLabel(AppLocalizations l10n, String serverName) {
  final parts = serverName.split(' - ').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return serverName;
  }
  final localized = parts.map((part) => _localizeServerVariantSegment(l10n, part)).toList();
  return localized.join(' - ');
}

String _localizeServerVariantSegment(AppLocalizations l10n, String segment) {
  final lower = segment.toLowerCase();
  if (lower == 'soft sub' || lower == 'softsub') {
    return l10n.oxplayerVariantSoftSub;
  }
  if (lower == 'hard sub' || lower == 'hardsub') {
    return l10n.oxplayerVariantHardSubGeneric;
  }
  if (lower == 'dubbed') {
    return l10n.oxplayerVariantDubbedGeneric;
  }
  final dubbed = RegExp(r'^dubbed\s*\(([^)]+)\)$', caseSensitive: false).firstMatch(segment);
  if (dubbed != null) {
    final lang = _localizedLanguageName(l10n, dubbed.group(1));
    return l10n.oxplayerVariantDubbed(lang);
  }
  final hardSub = RegExp(r'^hard sub\s*\(([^)]+)\)$', caseSensitive: false).firstMatch(segment);
  if (hardSub != null) {
    final lang = _localizedLanguageName(l10n, hardSub.group(1));
    return l10n.oxplayerVariantHardSub(lang);
  }
  if (_looksLikeLanguageSegment(segment)) {
    return _localizedLanguageName(l10n, segment);
  }
  return segment;
}

bool _looksLikeLanguageSegment(String segment) {
  switch (segment.toLowerCase()) {
    case 'english':
    case 'persian':
    case 'farsi':
    case 'arabic':
    case 'german':
    case 'french':
    case 'spanish':
    case 'russian':
    case 'japanese':
    case 'korean':
    case 'chinese':
    case 'turkish':
    case 'original':
    case 'dual':
      return true;
    default:
      return RegExp(r'^[a-z]{2,3}$', caseSensitive: false).hasMatch(segment);
  }
}

String _resolutionLabel(OxVersionStreamMeta meta, VersionStreamModel stream) {
  final height = meta.qualityHeight;
  if (height != null) {
    if (height >= 2160) return '2160p';
    if (height >= 1440) return '1440p';
    if (height >= 1080) return '1080p';
    if (height >= 720) return '720p';
    if (height >= 576) return '576p';
    if (height >= 480) return '480p';
    if (height >= 360) return '360p';
    return '${height}p';
  }
  final fromName = _segments(stream.name).firstOrNull;
  if (fromName != null && _looksLikeResolution(fromName)) {
    return fromName;
  }
  final detailed = stream.detailedResolutionLabel.trim();
  final firstToken = detailed.split(' ').firstOrNull;
  if (firstToken != null && _looksLikeResolution(firstToken)) {
    return firstToken;
  }
  return '';
}

String _sourceLabel(VersionStreamModel stream) {
  final segments = _segments(stream.name);
  if (segments.length >= 3) {
    return _normalizeSource(segments.last);
  }
  for (final segment in segments) {
    if (_looksLikeSource(segment)) {
      return _normalizeSource(segment);
    }
  }
  return '';
}

List<String> _segments(String name) {
  return name.split(' - ').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
}

bool _looksLikeResolution(String value) {
  final lower = value.toLowerCase();
  return lower == '4k' || RegExp(r'^\d+p$').hasMatch(lower);
}

bool _looksLikeSource(String value) {
  final lower = value.toLowerCase();
  if (_knownSourceTokens.contains(lower)) return true;
  return _normalizeSource(value) != value;
}

String _normalizeSource(String value) {
  final lower = value.toLowerCase();
  switch (lower) {
    case 'web-dl':
    case 'webdl':
      return 'WEB-DL';
    case 'webrip':
      return 'WEBRip';
    case 'bluray':
    case 'blu-ray':
      return 'BluRay';
    case 'hdtv':
      return 'HDTV';
    case 'remux':
      return 'REMUX';
    default:
      return value;
  }
}

String? _primaryLanguage(VersionStreamModel stream) {
  if (stream.audioStreams.isNotEmpty) {
    final audio = stream.audioStreams.firstWhere(
      (track) => track.language.trim().isNotEmpty,
      orElse: () => stream.audioStreams.first,
    );
    final fromAudio = audio.language.trim().isNotEmpty ? audio.language : audio.displayTitle;
    if (fromAudio.trim().isNotEmpty) {
      return fromAudio.trim();
    }
  }
  final blob = stream.name.toLowerCase();
  final dubbed = RegExp(r'dubbed\s*\(([^)]+)\)').firstMatch(blob);
  if (dubbed != null) {
    return dubbed.group(1)?.trim();
  }
  final hardSub = RegExp(r'hard sub\s*\(([^)]+)\)').firstMatch(blob);
  if (hardSub != null) {
    return hardSub.group(1)?.trim();
  }
  final segments = _segments(stream.name);
  if (segments.length == 3) {
    final middle = segments[1].toLowerCase();
    if (!middle.contains('dub') && !middle.contains('sub')) {
      return segments[1];
    }
  }
  if (segments.length == 2) {
    final middle = segments[1].toLowerCase();
    if (!middle.contains('dub') && !middle.contains('sub')) {
      return segments[1];
    }
  }
  return null;
}

String _middleLabel(AppLocalizations l10n, OxStreamDelivery delivery, String? language) {
  final lang = language?.trim();
  switch (delivery) {
    case OxStreamDelivery.dubbed:
      if (lang != null && lang.isNotEmpty) {
        return l10n.oxplayerVariantDubbed(lang);
      }
      return l10n.oxplayerVariantDubbedGeneric;
    case OxStreamDelivery.softSub:
      return l10n.oxplayerVariantSoftSub;
    case OxStreamDelivery.hardSub:
      if (lang != null && lang.isNotEmpty) {
        return l10n.oxplayerVariantHardSub(lang);
      }
      return l10n.oxplayerVariantHardSubGeneric;
    case OxStreamDelivery.original:
    case OxStreamDelivery.unknown:
      return lang ?? '';
  }
}

String _localizedLanguageName(AppLocalizations l10n, String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) {
    return '';
  }
  switch (value.toLowerCase()) {
    case 'en':
    case 'eng':
    case 'english':
      return l10n.oxplayerVariantLangEnglish;
    case 'fa':
    case 'fas':
    case 'per':
    case 'persian':
    case 'farsi':
      return l10n.oxplayerVariantLangPersian;
    case 'ar':
    case 'ara':
    case 'arabic':
      return l10n.oxplayerVariantLangArabic;
    case 'tr':
    case 'tur':
    case 'turkish':
      return l10n.oxplayerVariantLangTurkish;
    case 'de':
    case 'deu':
    case 'ger':
    case 'german':
      return l10n.oxplayerVariantLangGerman;
    case 'fr':
    case 'fra':
    case 'fre':
    case 'french':
      return l10n.oxplayerVariantLangFrench;
    case 'es':
    case 'spa':
    case 'spanish':
      return l10n.oxplayerVariantLangSpanish;
    case 'ru':
    case 'rus':
    case 'russian':
      return l10n.oxplayerVariantLangRussian;
    case 'ja':
    case 'jpn':
    case 'japanese':
      return l10n.oxplayerVariantLangJapanese;
    case 'ko':
    case 'kor':
    case 'korean':
      return l10n.oxplayerVariantLangKorean;
    case 'zh':
    case 'zho':
    case 'chi':
    case 'cmn':
    case 'chinese':
      return l10n.oxplayerVariantLangChinese;
    default:
      if (value.length <= 3) {
        return value.toUpperCase();
      }
      return value;
  }
}
