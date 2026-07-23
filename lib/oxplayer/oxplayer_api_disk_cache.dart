import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-backed JSON/HTTP body cache for OX SWR (survives app kill / screen dispose).
///
/// Keys are scoped by [userId] so account switch cannot leak another user's feed.
abstract final class OxplayerApiDiskCache {
  static const _dirName = 'ox_api_swr';
  static const _metaVersion = 1;

  /// Max age kept on disk; entries older than this are ignored (still deleted lazily).
  static const maxAge = Duration(days: 14);

  static Directory? _dir;
  static Future<Directory?>? _dirFuture;

  static Future<Directory?> _cacheDir() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    _dirFuture ??= () async {
      try {
        final root = await getApplicationSupportDirectory();
        final dir = Directory('${root.path}${Platform.pathSeparator}$_dirName');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        _dir = dir;
        return dir;
      } catch (_) {
        return null;
      }
    }();
    return _dirFuture;
  }

  static String key({
    required String userId,
    required String method,
    required Uri uri,
  }) {
    final normalized = uri.replace(fragment: '');
    final raw = '$userId|${method.toUpperCase()}|${normalized.toString()}';
    return _fnv1aHex(utf8.encode(raw));
  }

  /// Dual 32-bit FNV-1a as 16-char hex (JS-safe; no crypto package).
  static String _fnv1aHex(List<int> bytes) {
    var h1 = 0x811c9dc5;
    var h2 = 0x811c9dc5 ^ 0x9e3779b9;
    for (final b in bytes) {
      h1 ^= b;
      h1 = (h1 * 16777619) & 0xFFFFFFFF;
      h2 ^= b;
      h2 = (h2 * 16777619) & 0xFFFFFFFF;
    }
    return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0')}';
  }

  static Future<OxplayerApiDiskCacheEntry?> read(String key) async {
    final dir = await _cacheDir();
    if (dir == null) return null;
    final file = File('${dir.path}${Platform.pathSeparator}$key.json');
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final entry = OxplayerApiDiskCacheEntry.fromJson(decoded);
      if (entry.version != _metaVersion) {
        unawaitedDelete(file);
        return null;
      }
      if (DateTime.now().toUtc().difference(entry.savedAt) > maxAge) {
        unawaitedDelete(file);
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, OxplayerApiDiskCacheEntry entry) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}$key.json');
    try {
      await file.writeAsString(jsonEncode(entry.toJson()), flush: true);
    } catch (_) {
      // Best-effort cache; network remains source of truth.
    }
  }

  static Future<void> remove(String key) async {
    final dir = await _cacheDir();
    if (dir == null) return;
    final file = File('${dir.path}${Platform.pathSeparator}$key.json');
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Drop all SWR files (logout / account switch).
  static Future<void> clearAll() async {
    final dir = await _cacheDir();
    if (dir == null) return;
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _dir = null;
      _dirFuture = null;
    } catch (_) {}
  }

  static void unawaitedDelete(File file) {
    unawaited(file.delete());
  }
}

class OxplayerApiDiskCacheEntry {
  const OxplayerApiDiskCacheEntry({
    required this.savedAt,
    required this.statusCode,
    required this.body,
    this.headers = const {},
    this.version = 1,
  });

  final DateTime savedAt;
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final int version;

  factory OxplayerApiDiskCacheEntry.fromJson(Map<String, dynamic> json) {
    final headersRaw = json['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      for (final e in headersRaw.entries) {
        headers['${e.key}'] = '${e.value}';
      }
    }
    return OxplayerApiDiskCacheEntry(
      savedAt: DateTime.tryParse('${json['savedAt']}')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      statusCode: (json['statusCode'] as num?)?.toInt() ?? 200,
      body: '${json['body'] ?? ''}',
      headers: headers,
      version: (json['version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'savedAt': savedAt.toIso8601String(),
        'statusCode': statusCode,
        'headers': headers,
        'body': body,
      };
}
