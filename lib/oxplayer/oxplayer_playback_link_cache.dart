import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/oxplayer/oxplayer_playback_media_source.dart';
import 'package:fladder/oxplayer/oxplayer_tdlib_playback_resolver.dart';

/// In-memory PlaybackInfo cache keyed by Jellyfin MediaSource id (`ms_{variantId}`).
///
/// Process-lifetime only — cleared when the app process dies (kill / restart).
/// Entries remain valid for [ttl] while the process is alive.
abstract final class OxplayerPlaybackLinkCache {
  static const Duration ttl = Duration(hours: 2);

  static final Map<String, _Entry> _byMediaSourceId = {};

  static PlaybackInfoResponse? get(String? mediaSourceId) {
    final key = mediaSourceId?.trim() ?? '';
    if (key.isEmpty) return null;
    final entry = _byMediaSourceId[key];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _byMediaSourceId.remove(key);
      return null;
    }
    if (!_responseHasCommittedPlayableUrl(entry.response, mediaSourceId: key)) {
      _byMediaSourceId.remove(key);
      return null;
    }
    return entry.response;
  }

  static bool hasFresh(String? mediaSourceId) => get(mediaSourceId) != null;

  /// Stores [response] under every playable MediaSource id it contains (usually one).
  static void putFromResponse(PlaybackInfoResponse? response) {
    if (response == null) return;
    final sources = response.mediaSources;
    if (sources == null || sources.isEmpty) return;
    final now = DateTime.now();
    for (final source in sources) {
      final id = source.id?.trim() ?? '';
      if (id.isEmpty) continue;
      if (!oxplayerMediaSourceHasPlayableUrl(source)) continue;
      if (!_sourceIsCommittedPlayable(source)) continue;
      _byMediaSourceId[id] = _Entry(response: response, storedAt: now);
    }
  }

  static void invalidate(String? mediaSourceId) {
    final key = mediaSourceId?.trim() ?? '';
    if (key.isEmpty) return;
    _byMediaSourceId.remove(key);
  }

  /// Test / diagnostics only.
  static void clearAll() => _byMediaSourceId.clear();

  static int get debugEntryCount => _byMediaSourceId.length;
}

bool _sourceIsCommittedPlayable(MediaSourceInfo source) {
  final path = source.path?.trim() ?? '';
  if (!oxplayerIsTelegramProviderLink(path)) return true;
  final parsed = oxplayerParseTelegramDeliveryPath(path);
  return parsed != null && parsed.isCommitted;
}

bool _responseHasCommittedPlayableUrl(PlaybackInfoResponse response, {required String mediaSourceId}) {
  final source = oxplayerResolvePlaybackMediaSource(response, requestedMediaSourceId: mediaSourceId);
  if (source == null) return false;
  return _sourceIsCommittedPlayable(source);
}

class _Entry {
  _Entry({required this.response, required this.storedAt});

  final PlaybackInfoResponse response;
  final DateTime storedAt;

  bool get isFresh => DateTime.now().difference(storedAt) < OxplayerPlaybackLinkCache.ttl;
}
