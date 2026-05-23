import 'package:fladder/td_api_generated/td_api.dart' as td;
import 'package:fladder/oxplayer/telegram/tdlib_facade.dart';
import 'package:fladder/oxplayer/ox_sync_telegram_progress.dart';

Future<String?> platformResolveToStreamOrFileUrl({
  required TdlibFacade tdlib,
  required td.File resolvedFile,
  required td.Message? messageForMime,
  bool forOfflineSync = false,
  OxTelegramSyncProgressCallback? onSyncProgress,
}) async => null;
