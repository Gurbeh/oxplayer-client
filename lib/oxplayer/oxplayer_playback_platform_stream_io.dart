import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';
import 'package:fladder/oxplayer/telegram_local_stream_log.dart';
import 'package:fladder/oxplayer/telegram/telegram_range_playback.dart';

String? _mimeFromMessage(td.Message? message) {
  final content = message?.content;
  if (content is td.MessageVideo) return content.video.mimeType;
  if (content is td.MessageDocument) return content.document.mimeType;
  return null;
}

Future<String?> _downloadTelegramFileFully(
  TdlibFacade tdlib,
  int fileId, {
  OxTelegramSyncProgressCallback? onProgress,
}) async {
  try {
    await tdlib.send(td.DownloadFile(
        fileId: fileId, priority: 5, offset: 0, limit: 0, synchronous: false));
  } catch (_) {}

  const pollInterval = Duration(milliseconds: 320);
  var lastDownloaded = 0;
  var lastProgressAt = DateTime.now();

  while (true) {
    final fileResult = await tdlib.send(td.GetFile(fileId: fileId));
    if (fileResult is! td.File) return null;

    final srcPath = fileResult.local.path.trim();
    final downloaded = fileResult.local.downloadedSize;
    final total = fileResult.size > 0
        ? fileResult.size
        : (fileResult.expectedSize > 0 ? fileResult.expectedSize : 0);

    if (onProgress != null && total > 0) {
      final now = DateTime.now();
      final dt = now.difference(lastProgressAt).inMilliseconds;
      String? speedLabel;
      if (dt >= 400 && downloaded >= lastDownloaded) {
        final bps = (downloaded - lastDownloaded) * 1000 / dt;
        speedLabel = oxSyncFormatBytesPerSec(bps);
        lastDownloaded = downloaded;
        lastProgressAt = now;
      }
      onProgress(
        (downloaded / total).clamp(0.0, 1.0),
        downloadedBytes: downloaded,
        totalBytes: total,
        speedLabel: speedLabel,
      );
    }

    if (srcPath.isNotEmpty && fileResult.local.isDownloadingCompleted) {
      if (onProgress != null && total > 0) {
        onProgress(
          1.0,
          downloadedBytes: total,
          totalBytes: total,
          speedLabel: '',
        );
      }
      return srcPath;
    }

    await Future<void>.delayed(pollInterval);
  }
}

Future<String?> _waitForReadableVideoPrefix(
    TdlibFacade tdlib, int fileId) async {
  const minVideoPrefixBytes = 768 * 1024;
  const maxTdlibDownloadLimit = 4 * 1024 * 1024;
  const prefixWait = Duration(seconds: 26);
  const pollInterval = Duration(milliseconds: 380);

  final deadline = DateTime.now().add(prefixWait);
  while (DateTime.now().isBefore(deadline)) {
    td.File? file;
    try {
      final obj = await tdlib.send(td.GetFile(fileId: fileId));
      if (obj is td.File) file = obj;
    } catch (_) {}

    if (file != null) {
      final path = file.local.path.trim();
      final downloaded = file.local.downloadedSize;
      final total = file.size;
      if (path.isNotEmpty && file.local.isDownloadingCompleted) {
        return path;
      }
      if (total > 0 && path.isNotEmpty && downloaded >= total) {
        return path;
      }
      if (path.isNotEmpty && downloaded >= minVideoPrefixBytes) {
        return path;
      }
    }

    try {
      await tdlib.send(
        td.DownloadFile(
            fileId: fileId,
            priority: 8,
            offset: 0,
            limit: maxTdlibDownloadLimit,
            synchronous: false),
      );
    } catch (_) {}

    await Future<void>.delayed(pollInterval);
  }

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
    oxTelegramLocalStreamLog(
      'sync',
      'full TDLib download fileId=${resolvedFile.id} bytes=${resolvedFile.expectedSize}',
    );
    final downloadedPath = await _downloadTelegramFileFully(
      tdlib,
      resolvedFile.id,
      onProgress: onSyncProgress,
    );
    if (downloadedPath != null && downloadedPath.isNotEmpty) {
      oxTelegramLocalStreamLog('sync', 'OK file $downloadedPath');
      return Uri.file(downloadedPath).toString();
    }
    oxTelegramLocalStreamLog('sync', 'FAIL full download');
    return null;
  }

  final mime = messageForMime != null ? _mimeFromMessage(messageForMime) : null;
  final streamUrl = await TelegramRangePlayback.instance.openResolvedFile(
    tdlib: tdlib,
    file: resolvedFile,
    mimeType: mime,
  );
  if (streamUrl != null) {
    oxTelegramLocalStreamLog(
        'stream', 'OK fileId=${resolvedFile.id} → $streamUrl');
    return streamUrl.toString();
  }

  oxTelegramLocalStreamLog('stream', 'loopback failed → prefix on disk');
  final quickStartPath =
      await _waitForReadableVideoPrefix(tdlib, resolvedFile.id);
  if (quickStartPath != null && quickStartPath.isNotEmpty) {
    oxTelegramLocalStreamLog('stream', 'file prefix $quickStartPath');
    return Uri.file(quickStartPath).toString();
  }

  oxTelegramLocalStreamLog('stream', 'prefix timeout → full download');
  final downloadedPath =
      await _downloadTelegramFileFully(tdlib, resolvedFile.id);
  if (downloadedPath != null && downloadedPath.isNotEmpty) {
    oxTelegramLocalStreamLog('stream', 'file full $downloadedPath');
    return Uri.file(downloadedPath).toString();
  }

  oxTelegramLocalStreamLog('stream', 'FAIL no playable url');
  return null;
}
