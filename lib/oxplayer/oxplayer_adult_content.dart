import 'package:flutter/material.dart';

import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';

/// OX-only adult-content chip for library and Seerr detail headers.
abstract final class OxplayerAdultContent {
  static const adultTag = 'ox:adult';

  static bool isAdult({
    List<String> tags = const [],
    String? officialRating,
    Iterable<String>? keywords,
  }) {
    if (!OxplayerConfig.isEnabled) return false;
    if (tags.contains(adultTag)) return true;
    if (_isAdultOfficialRating(officialRating)) return true;
    if (keywords != null && _hasAdultKeywords(keywords)) return true;
    return false;
  }

  static SimpleLabel? chip({
    List<String> tags = const [],
    String? officialRating,
    Iterable<String>? keywords,
  }) {
    if (!isAdult(tags: tags, officialRating: officialRating, keywords: keywords)) {
      return null;
    }
    return const SimpleLabel(
      iconWidget: Text('🔞', style: TextStyle(fontSize: 18)),
    );
  }

  static List<SimpleLabel> labels({
    List<String> tags = const [],
    String? officialRating,
    Iterable<String>? keywords,
  }) {
    final label = chip(tags: tags, officialRating: officialRating, keywords: keywords);
    return label != null ? [label] : const [];
  }

  static bool _isAdultOfficialRating(String? rating) {
    final r = (rating ?? '').trim().toUpperCase().replaceAll(' ', '');
    if (r.isEmpty) return false;

    const nonAdult = ['PG-13', 'PG13', 'TV-14', 'TV-PG', 'TV-G', 'TV-Y', 'PG', 'G', 'U', 'MA15+'];
    for (final safe in nonAdult) {
      if (r == safe || r.contains(safe)) return false;
    }

    const adultExact = ['NC-17', 'NC17', 'TV-MA', 'R18+', 'R18', 'VM18', '+18', '18+', 'IIIB', 'XXX', 'X', 'R'];
    for (final mature in adultExact) {
      if (r == mature) return true;
    }

    if (r.contains('18') || r.contains('MATURE') || r.contains('ADULT')) {
      return true;
    }
    return false;
  }

  static bool _hasAdultKeywords(Iterable<String> keywords) {
    final pattern = RegExp(
      r'(^|[^a-z])(sexual|sex|nudity|erotic|erotica|softcore|pornograph|graphic sexuality|female frontal nudity|male frontal nudity|female nudity|male nudity|full frontal nudity)([^a-z]|$)',
      caseSensitive: false,
    );
    for (final kw in keywords) {
      final name = kw.trim();
      if (name.isEmpty) continue;
      if (pattern.hasMatch(name.toLowerCase())) return true;
    }
    return false;
  }
}
