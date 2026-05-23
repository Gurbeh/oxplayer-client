import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:fladder/td_api_generated/td_api.dart' as td;

import 'package:fladder/oxplayer/oxplayer_dotenv.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/telegram_local_stream_log.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/auth_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_runtime.dart';
import 'package:fladder/oxplayer/telegram/oxplayer_telegram_td_session.dart';
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/telegram/telegram_locator_env_search_chats.dart';
import 'package:fladder/oxplayer/telegram/telegram_media_file_locator_resolver.dart'
    show ResolvedTelegramMediaFile, resolveTelegramMediaFile, oxPlaybackMimeHintFromTdMessage;
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';
import 'package:fladder/oxplayer/oxplayer_playback_platform_stream.dart';

const bool _kOxTelegramLocatorVerbose = bool.fromEnvironment(
  'OX_TELEGRAM_LOCATOR_VERBOSE',
  defaultValue: false,
);

const bool _kOxProviderBackupVerbose = bool.fromEnvironment(
  'OX_PROVIDER_BACKUP_VERBOSE',
  defaultValue: false,
);

String _truncateForLog(String s, {int max = 160}) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…(+${t.length - max} chars)';
}

void _providerTmeLog(String detail) {
  oxTelegramLocalStreamLog('provider.tme', detail);
}

String _describeMessageContent(td.Message message) {
  final c = message.content;
  return c.runtimeType.toString();
}

String? _normalizePublicTmeUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final withScheme = t.startsWith('http') ? t : 'https://$t';
  final u = Uri.tryParse(withScheme);
  if (u == null || u.host.toLowerCase() != 't.me') return null;
  return Uri(
    scheme: 'https',
    host: 't.me',
    pathSegments: u.pathSegments.where((s) => s.isNotEmpty).toList(),
  ).toString();
}

Future<void> _providerOpenChatBestEffort(TdlibFacade tdlib, int chatId) async {
  try {
    await tdlib.send(td.OpenChat(chatId: chatId));
    if (_kOxProviderBackupVerbose) {
      _providerTmeLog('OpenChat(chatId=$chatId) OK');
    }
  } on td.TdError catch (e) {
    _providerTmeLog(
        'OpenChat(chatId=$chatId) TdError code=${e.code} message=${e.message}');
  }
}

Future<({td.Message? msg, td.TdError? err})> _providerGetMessageOnce(
  TdlibFacade tdlib, {
  required int chatId,
  required int messageId,
}) async {
  try {
    final msgObj =
        await tdlib.send(td.GetMessage(chatId: chatId, messageId: messageId));
    return (msg: msgObj is td.Message ? msgObj : null, err: null);
  } on td.TdError catch (e) {
    return (msg: null, err: e);
  }
}

Future<void> _oxLogGeneralVideoProviderBotReachable(TdlibFacade tdlib) async {
  final u = OxplayerEnv.providerBotUsername?.trim();
  if (u == null || u.isEmpty) {
    oxTelegramLocalStreamLog(
      'general_video',
      'PROVIDER_BOT_USERNAME unset — cannot preflight provider-bot chat',
    );
    return;
  }
  try {
    final obj = await tdlib.send(td.SearchPublicChat(username: u));
    if (obj is td.Chat) {
      oxTelegramLocalStreamLog(
        'general_video',
        'provider bot OK chatId=${obj.id}',
      );
    } else {
      oxTelegramLocalStreamLog(
        'general_video',
        'SearchPublicChat(@$u) → ${obj.runtimeType}',
      );
    }
  } on td.TdError catch (e) {
    oxTelegramLocalStreamLog(
      'general_video',
      'SearchPublicChat(@$u) code=${e.code} — open the provider bot in Telegram and tap Start, then retry playback',
    );
  }
}

class _OxLibraryFileDto {
  _OxLibraryFileDto({
    required this.id,
    required this.mediaId,
    required this.fileUniqueId,
    this.locatorType,
    this.locatorChatId,
    this.locatorMessageId,
    this.locatorRemoteFileId,
  });

  final String id;
  final String mediaId;
  final String fileUniqueId;
  final String? locatorType;
  final int? locatorChatId;
  final int? locatorMessageId;
  final String? locatorRemoteFileId;

  static _OxLibraryFileDto? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['id']?.toString();
    final mediaId = m['mediaId']?.toString();
    final fu = m['fileUniqueId']?.toString();
    if (id == null || mediaId == null || fu == null) return null;
    return _OxLibraryFileDto(
      id: id,
      mediaId: mediaId,
      fileUniqueId: fu,
      locatorType: m['locatorType']?.toString(),
      locatorChatId: _parseInt(m['locatorChatId']),
      locatorMessageId: _parseInt(m['locatorMessageId']),
      locatorRemoteFileId: m['locatorRemoteFileId']?.toString(),
    );
  }
}

int? _parseInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString());
}

class _OxLibraryDetailDto {
  _OxLibraryDetailDto({
    required this.files,
    this.providerBackupPostUrl,
    this.isGeneralVideo = false,
  });

  final List<_OxLibraryFileDto> files;
  final String? providerBackupPostUrl;
  final bool isGeneralVideo;

  static _OxLibraryDetailDto? tryParseBody(String body) {
    final dec = jsonDecode(body);
    if (dec is! Map) return null;
    final filesRaw = dec['files'];
    if (filesRaw is! List) return null;
    final mediaRaw = dec['media'];
    String? trimmedBackup = mediaRaw is Map
        ? (mediaRaw['providerBackupPostUrl'] ??
                mediaRaw['provider_backup_post_url'])
            ?.toString()
            .trim()
        : null;
    if (trimmedBackup != null && trimmedBackup.isEmpty) trimmedBackup = null;
    final mediaType =
        mediaRaw is Map ? mediaRaw['type']?.toString().trim() : null;
    final isGeneralVideo = mediaType == 'GENERAL_VIDEO';
    final files = <_OxLibraryFileDto>[];
    for (final f in filesRaw) {
      final p = _OxLibraryFileDto.tryParse(f);
      if (p != null) files.add(p);
    }
    return _OxLibraryDetailDto(
      files: files,
      providerBackupPostUrl: trimmedBackup,
      isGeneralVideo: isGeneralVideo,
    );
  }
}

Future<_OxLibraryDetailDto?> _fetchLibraryMediaDetail(
    Ref ref, String globalId) async {
  final serverUrl = ref.read(serverUrlProvider);
  final login = ref.read(userProvider)?.credentials ??
      ref.read(authProvider).serverLoginModel?.tempCredentials;
  if (serverUrl == null || serverUrl.isEmpty || login == null) return null;

  final uri = Uri.parse(serverUrl).resolve('me/library/media/$globalId');
  final response = await http.get(uri, headers: login.header(ref));
  if (response.statusCode != 200) {
    oxTelegramLocalStreamLog(
        'prep FAIL', 'library HTTP ${response.statusCode}');
    return null;
  }
  return _OxLibraryDetailDto.tryParseBody(response.body);
}

Future<bool?> _postRecoverFromBackup(
  Ref ref,
  String mediaFileId, {
  bool fresh = false,
}) async {
  final serverUrl = ref.read(serverUrlProvider);
  final login = ref.read(userProvider)?.credentials ??
      ref.read(authProvider).serverLoginModel?.tempCredentials;
  if (serverUrl == null || serverUrl.isEmpty || login == null) return null;

  final uri = Uri.parse(serverUrl).resolve('me/recover-from-backup');
  final headers = Map<String, String>.from(login.header(ref));
  headers['Content-Type'] = 'application/json; charset=utf-8';

  try {
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(<String, dynamic>{
        'mediaFileId': mediaFileId,
        if (fresh) 'fresh': true,
      }),
    );
    if (response.statusCode != 200) {
      oxTelegramLocalStreamLog(
        'recover',
        'HTTP ${response.statusCode} body=${response.body.length > 500 ? "${response.body.substring(0, 500)}…" : response.body}',
      );
      return false;
    }
    final dec = jsonDecode(response.body);
    if (dec is Map) {
      final ok = dec['ok'] == true;
      final status = dec['status']?.toString();
      oxTelegramLocalStreamLog(
          'recover', 'ok=$ok status=$status attempts=${dec['attempts']}');
      return ok;
    }
    return false;
  } catch (e) {
    oxTelegramLocalStreamLog('recover', 'ERROR $e');
    return null;
  }
}

Future<String?> _resolveRecoveredProviderBackupUrl({
  required Ref ref,
  required TdlibFacade tdlib,
  required String mediaId,
  required String mediaFileId,
  required String overrideUrl,
  bool forOfflineSync = false,
  OxTelegramSyncProgressCallback? onSyncProgress,
}) async {
  final recovered = await _postRecoverFromBackup(ref, mediaFileId, fresh: true);
  if (recovered != true) {
    oxTelegramLocalStreamLog(
      'recover',
      'recover-from-backup failed or incomplete (recovered=$recovered). '
          'Ensure provider-bot runs and TELEGRAM_MEDIA_PROVIDERS is set on the server.',
    );
    return null;
  }
  final detailAfter = await _fetchLibraryMediaDetail(ref, mediaId);
  final backupAfter = overrideUrl.isNotEmpty
      ? overrideUrl
      : (detailAfter?.providerBackupPostUrl?.trim() ?? '');
  if (backupAfter.isEmpty) {
    oxTelegramLocalStreamLog(
      'recover',
      'recovery reported ok but providerBackupPostUrl still empty — refetch detail or check provider-bot logs',
    );
    return null;
  }
  oxTelegramLocalStreamLog(
    'recover.detail',
    'refetched backupPostUrl len=${backupAfter.length} excerpt=${_truncateForLog(backupAfter, max: 120)}',
  );
  final urlAfter = await _tryPlayableUrlFromProviderBackupPost(
    tdlib,
    backupAfter,
    forOfflineSync: forOfflineSync,
    onSyncProgress: onSyncProgress,
  );
  if (urlAfter == null) {
    oxTelegramLocalStreamLog(
      'tdlib.file',
      'FAIL provider URL after recovery — see provider.tme lines above (GetMessage / SearchPublicChat / channel access)',
    );
    return null;
  }
  oxTelegramLocalStreamLog('resolve.done', 'OK $urlAfter');
  return urlAfter;
}

String? _parseOxplayerTelegramMediaId(String uri) {
  final u = Uri.tryParse(uri.trim());
  if (u == null || u.scheme != 'oxplayer' || u.host != 'telegram') return null;
  final id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
  if (id == null || !RegExp(r'^\d+$').hasMatch(id)) return null;
  return id;
}

_OxLibraryFileDto? _pickFile(_OxLibraryDetailDto detail, String targetMediaId) {
  for (final f in detail.files) {
    if (f.mediaId == targetMediaId) return f;
  }
  for (final f in detail.files) {
    if (f.locatorChatId != null && f.locatorMessageId != null) return f;
  }
  return detail.files.isEmpty ? null : detail.files.first;
}

({String? username, int? internalChatId, int messageId})?
    _parseTmePostLinkForPlayback(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  late final Uri u;
  try {
    u = Uri.parse(trimmed.startsWith('http') ? trimmed : 'https://$trimmed');
  } catch (_) {
    return null;
  }
  if (u.host != 't.me') return null;
  final parts = u.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length >= 3 && parts[0] == 'c') {
    final digits = parts[1].replaceAll(RegExp(r'\D'), '');
    final msgId = int.tryParse(parts[2]);
    if (digits.isEmpty || msgId == null || msgId <= 0) return null;
    try {
      final chatId = int.parse('-100$digits');
      return (username: null, internalChatId: chatId, messageId: msgId);
    } catch (_) {
      return null;
    }
  }
  if (parts.length >= 2) {
    final user = parts[0].replaceFirst(RegExp(r'^@'), '');
    final msgId = int.tryParse(parts[1]);
    if (user.isEmpty || msgId == null || msgId <= 0) return null;
    return (username: user, internalChatId: null, messageId: msgId);
  }
  return null;
}

td.File? _extractPlayableFileFromMessage(td.Message message) {
  final content = message.content;
  if (content is td.MessageVideo) return content.video.video;
  if (content is td.MessageDocument) return content.document.document;
  if (content is td.MessageAnimation) return content.animation.animation;
  if (content is td.MessageVideoNote) return content.videoNote.video;
  return null;
}

Future<ResolvedTelegramMediaFile?> _resolveFromProviderBackupPostUrl(
  TdlibFacade tdlib,
  String providerBackupPostUrl,
) async {
  if (_kOxProviderBackupVerbose) {
    _providerTmeLog(
        'input url=${_truncateForLog(providerBackupPostUrl, max: 200)}');
  }

  final normalizedUrl = _normalizePublicTmeUrl(providerBackupPostUrl);
  if (normalizedUrl == null) {
    _providerTmeLog(
      'not a https://t.me/… URL excerpt=${_truncateForLog(providerBackupPostUrl)}',
    );
    return null;
  }

  late final td.MessageLinkInfo linkInfo;
  try {
    final obj = await tdlib.send(td.GetMessageLinkInfo(url: normalizedUrl));
    if (obj is! td.MessageLinkInfo) {
      _providerTmeLog('GetMessageLinkInfo → ${obj.runtimeType}');
      return null;
    }
    linkInfo = obj;
  } on td.TdError catch (e) {
    _providerTmeLog(
      'GetMessageLinkInfo TdError code=${e.code} message=${e.message}',
    );
    return null;
  }

  final chatId = linkInfo.chatId;
  _providerTmeLog(
    'GetMessageLinkInfo chatId=$chatId topic=${linkInfo.topicId} '
    'embeddedMessage=${linkInfo.message != null}',
  );

  if (chatId == 0) {
    _providerTmeLog('GetMessageLinkInfo returned chatId=0');
    return null;
  }

  await _providerOpenChatBestEffort(tdlib, chatId);

  td.Message? msgObj = linkInfo.message;
  if (msgObj == null) {
    final parsed = _parseTmePostLinkForPlayback(normalizedUrl);
    final mid = parsed?.messageId;
    if (mid != null && mid > 0) {
      final once =
          await _providerGetMessageOnce(tdlib, chatId: chatId, messageId: mid);
      msgObj = once.msg;
      if (msgObj == null && once.err != null) {
        _providerTmeLog(
          'GetMessage(chatId=$chatId, messageId=$mid) TdError '
          'code=${once.err!.code} message=${once.err!.message}',
        );
      }
    }
  }

  if (msgObj == null) {
    _providerTmeLog(
      'no Message — join TELEGRAM_MEDIA_PROVIDERS with this TDLib account if private',
    );
    return null;
  }

  final file = _extractPlayableFileFromMessage(msgObj);
  if (file == null) {
    _providerTmeLog(
      'message has no playable Video/Document/Animation/VideoNote '
      '(content=${_describeMessageContent(msgObj)} chatId=$chatId tdMessageId=${msgObj.id})',
    );
    return null;
  }

  if (_kOxProviderBackupVerbose) {
    final rid = file.remote.id;
    _providerTmeLog(
      'OK extracted file id=${file.id} remoteId=${rid.trim().isEmpty ? "?" : rid} '
      'expectedSize=${file.expectedSize}',
    );
  }

  return ResolvedTelegramMediaFile(
    file: file,
    locatorChatId: chatId,
    locatorMessageId: msgObj.id,
    locatorType: 'CHAT_MESSAGE',
    resolutionReason: 'provider_backup_post_url',
    mimeHint: oxPlaybackMimeHintFromTdMessage(msgObj),
  );
}

Future<String?> _tryPlayableUrlFromProviderBackupPost(
  TdlibFacade tdlib,
  String providerBackupPostUrl, {
  bool forOfflineSync = false,
  OxTelegramSyncProgressCallback? onSyncProgress,
}) async {
  final direct =
      await _resolveFromProviderBackupPostUrl(tdlib, providerBackupPostUrl);
  if (direct == null) return null;
  oxTelegramLocalStreamLog(
    'tdlib.file',
    'OK provider_backup_post_url fileId=${direct.file.id}',
  );
  return platformResolveToStreamOrFileUrl(
    tdlib: tdlib,
    resolvedFile: direct.file,
    messageForMime: null,
    forOfflineSync: forOfflineSync,
    onSyncProgress: onSyncProgress,
  );
}

Future<String?> resolveTelegramMessageToPlayableUrl({
  required td.Message message,
}) async {
  await OxplayerDotenv.ensureLoaded();
  final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
  if (!ready) {
    oxTelegramLocalStreamLog('my_tg.resolve', 'tdlib not ready');
    return null;
  }
  final file = _extractPlayableFileFromMessage(message);
  if (file == null) {
    oxTelegramLocalStreamLog('my_tg.resolve', 'no File in message content');
    return null;
  }
  final tdlib = OxplayerTelegramTdRuntime.facade;
  final url = await platformResolveToStreamOrFileUrl(
    tdlib: tdlib,
    resolvedFile: file,
    messageForMime: message,
  );
  if (url != null) {
    oxTelegramLocalStreamLog('my_tg.resolve', 'OK len=${url.length}');
  } else {
    oxTelegramLocalStreamLog('my_tg.resolve', 'FAIL');
  }
  return url;
}

Future<String?> downloadOxplayerTelegramMediaForSync({
  required Ref ref,
  required String mediaId,
  OxTelegramSyncProgressCallback? onProgress,
}) =>
    resolveOxplayerTelegramLocatorToPlayableUrl(
      oxplayerLocatorUri: 'oxplayer://telegram/$mediaId',
      ref: ref,
      forOfflineSync: true,
      onSyncProgress: onProgress,
    );

Future<String?> resolveOxplayerTelegramLocatorToPlayableUrl({
  required String oxplayerLocatorUri,
  required Ref ref,
  bool forOfflineSync = false,
  OxTelegramSyncProgressCallback? onSyncProgress,
}) async {
  if (forOfflineSync) {
    oxTelegramLocalStreamLog('sync', 'offline full-file download');
  }

  await OxplayerDotenv.ensureLoaded();

  final mediaId = _parseOxplayerTelegramMediaId(oxplayerLocatorUri);
  if (mediaId == null) {
    oxTelegramLocalStreamLog('prep ABORT', 'bad oxplayer locator');
    return null;
  }

  final providerOnly = OxplayerEnv.playbackProviderOnly;
  final overrideUrl = OxplayerEnv.playbackProviderPostUrlOverride;

  if (providerOnly && overrideUrl.isNotEmpty) {
    oxTelegramLocalStreamLog('prep',
        'OX_FALLBACK_PROVIDER_ONLY + override URL (skip library detail)');
    final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
    if (!ready) {
      oxTelegramLocalStreamLog(
          'tdlib.session', 'FAIL not authorized / not ready');
      return null;
    }
    final tdlib = OxplayerTelegramTdRuntime.facade;
    final url = await _tryPlayableUrlFromProviderBackupPost(
      tdlib,
      overrideUrl,
      forOfflineSync: forOfflineSync,
      onSyncProgress: onSyncProgress,
    );
    if (url != null) oxTelegramLocalStreamLog('resolve.done', 'OK $url');
    return url;
  }

  final detail = await _fetchLibraryMediaDetail(ref, mediaId);
  if (detail == null || detail.files.isEmpty) {
    oxTelegramLocalStreamLog(
        'prep FAIL', 'no library file row (need locator metadata)');
    return null;
  }

  final file = _pickFile(detail, mediaId);
  if (file == null) {
    oxTelegramLocalStreamLog('prep FAIL', 'pickFile empty');
    return null;
  }

  oxTelegramLocalStreamLog(
    'tdlib.session',
    'ensureReadyForPlayback mediaId=$mediaId locator=${file.locatorType} chat=${file.locatorChatId} msg=${file.locatorMessageId}',
  );
  final ready = await OxplayerTelegramTdSession.ensureReadyForPlayback();
  if (!ready) {
    oxTelegramLocalStreamLog(
        'tdlib.session', 'FAIL not authorized / not ready');
    return null;
  }
  oxTelegramLocalStreamLog('tdlib.session', 'OK');

  final tdlib = OxplayerTelegramTdRuntime.facade;
  final isGeneralVideo = detail.isGeneralVideo;

  final useApiBackup = overrideUrl.trim().isEmpty;
  var backup =
      useApiBackup ? (detail.providerBackupPostUrl?.trim() ?? '') : overrideUrl.trim();
  if (isGeneralVideo) {
    backup = '';
    oxTelegramLocalStreamLog(
      'prep',
      'GENERAL_VIDEO: ignoring provider t.me backup; TDLib locator / user provider DM + locator-heal only',
    );
  }

  if (!isGeneralVideo && backup.isEmpty && useApiBackup) {
    oxTelegramLocalStreamLog(
      'prep',
      'no providerBackupPostUrl → POST me/recover-from-backup (provision)',
    );
    final provisioned = await _postRecoverFromBackup(ref, file.mediaId, fresh: false);
    if (provisioned == true) {
      final detailAfter = await _fetchLibraryMediaDetail(ref, mediaId);
      backup = detailAfter?.providerBackupPostUrl?.trim() ?? '';
    }
  }

  if (backup.isNotEmpty) {
    var url = await _tryPlayableUrlFromProviderBackupPost(
      tdlib,
      backup,
      forOfflineSync: forOfflineSync,
      onSyncProgress: onSyncProgress,
    );
    if (url != null) {
      oxTelegramLocalStreamLog('resolve.done', 'OK $url');
      return url;
    }
    oxTelegramLocalStreamLog(
      'prep',
      'provider path failed (resolve or stream) → recover fresh + one retry',
    );

    if (useApiBackup) {
      final rotated = await _postRecoverFromBackup(ref, file.mediaId, fresh: true);
      if (rotated == true) {
        final detailFresh = await _fetchLibraryMediaDetail(ref, mediaId);
        final backup2 = detailFresh?.providerBackupPostUrl?.trim() ?? '';
        if (backup2.isNotEmpty) {
          url = await _tryPlayableUrlFromProviderBackupPost(
            tdlib,
            backup2,
            forOfflineSync: forOfflineSync,
            onSyncProgress: onSyncProgress,
          );
          if (url != null) {
            oxTelegramLocalStreamLog('resolve.done', 'OK $url');
            return url;
          }
        }
      }
    }

    if (providerOnly) {
      oxTelegramLocalStreamLog(
        'tdlib.file',
        'FAIL provider path (OX_FALLBACK_PROVIDER_ONLY — no locator fallback)',
      );
      return null;
    }
    oxTelegramLocalStreamLog(
      'prep',
      'provider path exhausted after fresh rotate → full locator chain',
    );
  } else if (providerOnly && !isGeneralVideo) {
    oxTelegramLocalStreamLog(
      'prep',
      'OX_FALLBACK_PROVIDER_ONLY: still no providerBackupPostUrl → recover-from-backup (fresh)',
    );
    return _resolveRecoveredProviderBackupUrl(
      ref: ref,
      tdlib: tdlib,
      mediaId: mediaId,
      mediaFileId: file.mediaId,
      overrideUrl: overrideUrl,
      forOfflineSync: forOfflineSync,
      onSyncProgress: onSyncProgress,
    );
  }

  void onDiag(String m) {
    if (!_kOxTelegramLocatorVerbose) return;
    oxTelegramLocalStreamLog('tdlib.resolve', m);
  }

  final envSearchChats =
      await oxplayerLocatorTagTelegramSearchChatIds(tdlib, onDiag);

  if (isGeneralVideo) {
    await _oxLogGeneralVideoProviderBotReachable(tdlib);
  }

  var resolvedMedia = await resolveTelegramMediaFile(
    tdlib: tdlib,
    mediaFileId: file.mediaId,
    fileUniqueId: file.fileUniqueId,
    locatorType: file.locatorType,
    locatorChatId: file.locatorChatId,
    locatorMessageId: file.locatorMessageId,
    locatorRemoteFileId: file.locatorRemoteFileId,
    locatorTagTelegramSearchChatIds: envSearchChats,
    onDiagnostic: onDiag,
  );

  if (resolvedMedia == null && isGeneralVideo) {
    oxTelegramLocalStreamLog(
      'tdlib.file',
      'GENERAL_VIDEO locator failed → POST /me/recover-from-backup (provider-bot copies clone/backup to user DM + locator)',
    );
    final recovered = await _postRecoverFromBackup(ref, file.mediaId, fresh: false);
    if (recovered == true) {
      final detailAfter = await _fetchLibraryMediaDetail(ref, mediaId);
      final fileAfter =
          detailAfter != null ? _pickFile(detailAfter, mediaId) : null;
      if (fileAfter != null) {
        resolvedMedia = await resolveTelegramMediaFile(
          tdlib: tdlib,
          mediaFileId: fileAfter.mediaId,
          fileUniqueId: fileAfter.fileUniqueId,
          locatorType: fileAfter.locatorType,
          locatorChatId: fileAfter.locatorChatId,
          locatorMessageId: fileAfter.locatorMessageId,
          locatorRemoteFileId: fileAfter.locatorRemoteFileId,
          locatorTagTelegramSearchChatIds: envSearchChats,
          onDiagnostic: onDiag,
        );
      }
    } else {
      oxTelegramLocalStreamLog(
        'recover',
        'recover-from-backup did not succeed (recovered=$recovered) — check provider-bot + clone access',
      );
    }
  }

  if (resolvedMedia == null) {
    if (isGeneralVideo) {
      oxTelegramLocalStreamLog(
        'tdlib.file',
        'FAIL GENERAL_VIDEO — still no playable locator after recovery; '
            'ensure provider-bot runs, TELEGRAM_PROVIDER_BOT_USERNAME matches the bot that DMed you, '
            'or POST /me/library/media/locator-heal manually',
      );
      return null;
    }
    oxTelegramLocalStreamLog(
        'tdlib.file', 'FAIL (no message/file) → API recover-from-backup');
    return _resolveRecoveredProviderBackupUrl(
      ref: ref,
      tdlib: tdlib,
      mediaId: mediaId,
      mediaFileId: file.mediaId,
      overrideUrl: overrideUrl,
      forOfflineSync: forOfflineSync,
      onSyncProgress: onSyncProgress,
    );
  }
  oxTelegramLocalStreamLog(
    'tdlib.file',
    'OK fileId=${resolvedMedia.file.id} reason=${resolvedMedia.resolutionReason ?? "?"} '
        'expectedSize=${resolvedMedia.file.expectedSize}',
  );

  final url = await platformResolveToStreamOrFileUrl(
    tdlib: tdlib,
    resolvedFile: resolvedMedia.file,
    messageForMime: null,
    forOfflineSync: forOfflineSync,
    onSyncProgress: onSyncProgress,
  );
  if (url == null) {
    oxTelegramLocalStreamLog('resolve.done', 'FAIL');
  } else {
    oxTelegramLocalStreamLog('resolve.done', 'OK $url');
  }
  return url;
}
