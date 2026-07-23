import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fladder/oxplayer/oxplayer_api_disk_cache.dart';

/// Wraps [http.Client] so allowlisted GETs do stale-while-revalidate from disk.
///
/// Cold open / screen revisit: return cached bytes immediately (Chopper converts).
/// Background: refetch, rewrite disk. Same-session UI updates only when caller
/// refetches (pull-to-refresh / navigate). Home/Feed uses its own double-apply path.
class OxplayerSwrHttpClient extends http.BaseClient {
  OxplayerSwrHttpClient({
    required http.Client inner,
    required String Function() userId,
  })  : _inner = inner,
        _userId = userId;

  final http.Client _inner;
  final String Function() _userId;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_shouldCache(request)) {
      return _inner.send(request);
    }

    final userId = _userId().trim();
    if (userId.isEmpty) {
      return _inner.send(request);
    }

    final cacheKey = OxplayerApiDiskCache.key(
      userId: userId,
      method: request.method,
      uri: request.url,
    );

    final cached = await OxplayerApiDiskCache.read(cacheKey);
    if (cached != null && cached.statusCode >= 200 && cached.statusCode < 300 && cached.body.isNotEmpty) {
      unawaited(_revalidate(request, cacheKey));
      return _entryToStreamed(cached, request);
    }

    return _sendAndStore(request, cacheKey);
  }

  Future<void> _revalidate(http.BaseRequest request, String cacheKey) async {
    try {
      final clone = await _cloneRequest(request);
      if (clone == null) return;
      await _sendAndStore(clone, cacheKey);
    } catch (_) {}
  }

  Future<http.StreamedResponse> _sendAndStore(http.BaseRequest request, String cacheKey) async {
    final streamed = await _inner.send(request);
    final bytes = await streamed.stream.toBytes();
    if (streamed.statusCode >= 200 && streamed.statusCode < 300 && bytes.isNotEmpty) {
      final headers = <String, String>{};
      streamed.headers.forEach((k, v) {
        headers[k] = v;
      });
      await OxplayerApiDiskCache.write(
        cacheKey,
        OxplayerApiDiskCacheEntry(
          savedAt: DateTime.now().toUtc(),
          statusCode: streamed.statusCode,
          body: utf8.decode(bytes, allowMalformed: true),
          headers: headers,
        ),
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      streamed.statusCode,
      contentLength: bytes.length,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  static http.StreamedResponse _entryToStreamed(OxplayerApiDiskCacheEntry entry, http.BaseRequest request) {
    final bytes = utf8.encode(entry.body);
    final headers = Map<String, String>.from(entry.headers);
    headers.putIfAbsent('content-type', () => 'application/json');
    headers['x-ox-swr'] = 'hit';
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      entry.statusCode,
      contentLength: bytes.length,
      request: request,
      headers: headers,
    );
  }

  /// Clone is only needed for GET without body (our allowlist).
  static Future<http.BaseRequest?> _cloneRequest(http.BaseRequest request) async {
    if (request is! http.Request) return null;
    final clone = http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    clone.headers.addAll(request.headers);
    clone.bodyBytes = request.bodyBytes;
    return clone;
  }

  static bool _shouldCache(http.BaseRequest request) => oxSwrShouldCacheRequest(request);

  @override
  void close() => _inner.close();
}

/// Visible for tests / allowlist docs.
bool oxSwrShouldCacheRequest(http.BaseRequest request) {
  if (request.method.toUpperCase() != 'GET') return false;
  final path = request.url.path;
  if (path.isEmpty) return false;

  final lower = path.toLowerCase();
  if (lower.contains('/sessions')) return false;
  if (lower.contains('/playbackinfo')) return false;
  if (lower.contains('/authenticate')) return false;
  if (lower.contains('/images/')) return false;
  if (lower.contains('/videos/')) return false;
  if (lower.contains('/audio/')) return false;
  if (lower.endsWith('/me') && lower.contains('/users/')) return false;

  if (lower.contains('/users/') && lower.contains('/views')) return true;
  if (lower.contains('/items/latest')) return true;
  if (lower.contains('/items/resume')) return true;
  if (lower.contains('/shows/nextup')) return true;
  // Series catalog (seasons / episodes) — needed for Play target on revisit.
  if (lower.contains('/shows/') && (lower.contains('/seasons') || lower.contains('/episodes'))) {
    return true;
  }
  if (lower.contains('/items')) return true;
  if (lower.contains('/genres')) return true;
  if (lower.contains('/persons')) return true;
  if (lower.contains('/studios')) return true;
  return false;
}
