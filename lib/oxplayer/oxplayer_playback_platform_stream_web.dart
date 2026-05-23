import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart';

import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';
import 'package:fladder/oxplayer/telegram_local_stream_log.dart';

void _webPlayLog(String context, String message) {
  oxTelegramLocalStreamLog('web.$context', message);
}

JSObject get _windowObj => window as JSObject;

JSObject? _tdwebBridgeObj() {
  final raw = _windowObj.getProperty<JSAny?>('oxplayerTdweb'.toJS);
  if (raw == null) return null;
  try {
    return raw as JSObject;
  } catch (_) {
    return null;
  }
}

String _jsAnyToDartString(JSAny? value) {
  if (value == null) return '';
  try {
    return (value as JSString).toDart;
  } catch (_) {}
  try {
    final d = value.dartify();
    if (d is String) return d;
    return d?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

String? _mimeFromMessage(td.Message? message) {
  final content = message?.content;
  if (content is td.MessageVideo) return content.video.mimeType;
  if (content is td.MessageDocument) return content.document.mimeType;
  return null;
}

Future<td.File?> _prepareFileForTdwebStreaming(TdlibFacade tdlib, td.File source) async {
  _webPlayLog('download', 'prepare stream fileId=${source.id} size=${source.size} expected=${source.expectedSize}');
  try {
    await tdlib.send(td.DownloadFile(
      fileId: source.id,
      priority: 32,
      offset: 0,
      limit: 4 * 1024 * 1024,
      synchronous: false,
    ));
  } catch (_) {}

  final deadline = DateTime.now().add(const Duration(seconds: 24));
  while (DateTime.now().isBefore(deadline)) {
    final obj = await tdlib.send(td.GetFile(fileId: source.id));
    if (obj is! td.File) return null;
    final path = obj.local.path.trim();
    final total = obj.size > 0 ? obj.size : obj.expectedSize;
    _webPlayLog(
      'download',
      'poll path=${path.isNotEmpty} completed=${obj.local.isDownloadingCompleted} '
          'offset=${obj.local.downloadOffset} prefix=${obj.local.downloadedPrefixSize} '
          'downloaded=${obj.local.downloadedSize} total=$total',
    );
    if (path.isNotEmpty && obj.local.downloadOffset == 0 && obj.local.downloadedPrefixSize >= 512 * 1024) {
      return obj;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  _webPlayLog('download', 'prepare timeout');
  return null;
}

Future<String?> _streamUrlFromTdwebFile(td.File file, {String? mimeType}) async {
  final path = file.local.path.trim();
  final size = file.size > 0 ? file.size : file.expectedSize;
  _webPlayLog(
    'stream',
    'create fileId=${file.id} mime=${mimeType ?? "null"} size=$size pathLen=${path.length}',
  );
  if (path.isEmpty || size <= 0) {
    _webPlayLog('stream', 'missing path/size path=${path.isNotEmpty} size=$size');
    return null;
  }
  final bridge = _tdwebBridgeObj();
  if (bridge == null) {
    _webPlayLog('stream', 'oxplayerTdweb bridge missing');
    return null;
  }
  final promise = bridge.callMethodVarArgs<JSPromise<JSAny?>>(
    'createStreamUrlForTdFile'.toJS,
    <JSAny?>[
      file.id.toJS,
      path.toJS,
      size.toJS,
      (mimeType == null || mimeType.isEmpty ? 'video/mp4' : mimeType).toJS,
    ],
  );
  final JSAny? result;
  try {
    result = await promise.toDart.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    _webPlayLog('stream', 'create URL timed out; falling back to server playback');
    return null;
  } catch (e) {
    _webPlayLog('stream', 'create URL failed $e');
    return null;
  }
  final raw = _jsAnyToDartString(result).trim();
  String? url;
  String? sniffedMime;
  String? webPlaybackRisk;
  var parsedJson = false;
  if (raw.startsWith('{')) {
    try {
      final dec = jsonDecode(raw);
      if (dec is Map) {
        parsedJson = true;
        final u = dec['url'];
        url = u == null ? null : u.toString();
        if (url == 'null') url = null;
        sniffedMime = dec['sniffedMime']?.toString();
        final risk = dec['webPlaybackRisk'];
        if (risk != null && risk.toString().isNotEmpty && risk.toString() != 'null') {
          webPlaybackRisk = risk.toString();
        }
      }
    } catch (_) {}
  }
  if (!parsedJson) {
    url = raw.isEmpty ? null : raw;
  }
  if (url == null || url.isEmpty) {
    _webPlayLog('stream', 'no stream URL sniffedMime=$sniffedMime');
    return null;
  }
  if (url.contains('/__ox_tdweb_stream/')) {
    _webPlayLog(
      'stream',
      'OK len=${url.length} sniffedMime=${sniffedMime ?? "null"} '
      'webPlaybackRisk=${webPlaybackRisk ?? "none"}',
    );
    if (webPlaybackRisk != null) {
      _webPlayLog(
        'stream',
        'web may not play in Chrome <video>: $webPlaybackRisk '
        '(Android TDLib+MPV or server transcode)',
      );
    }
    return url;
  }
  _webPlayLog('stream', 'unexpected result len=${url.length}');
  return null;
}

Future<String?> platformResolveToStreamOrFileUrl({
  required TdlibFacade tdlib,
  required td.File resolvedFile,
  required td.Message? messageForMime,
  bool forOfflineSync = false,
  OxTelegramSyncProgressCallback? onSyncProgress,
}) async {
  if (forOfflineSync) {
    _webPlayLog('sync', 'full offline download not implemented on web');
    return null;
  }
  final prepared = await _prepareFileForTdwebStreaming(tdlib, resolvedFile);
  if (prepared == null) {
    _webPlayLog('stream', 'prepare failed fileId=${resolvedFile.id}');
    return null;
  }
  return _streamUrlFromTdwebFile(
    prepared,
    mimeType: _mimeFromMessage(messageForMime),
  );
}
