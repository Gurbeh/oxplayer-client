import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';

/// Persian / Iranian language detection for OX subtitle UI.
abstract final class OxPersianLanguage {
  static const _languageCodes = {
    'fa',
    'fas',
    'per',
    'pes',
    'fae',
  };

  static bool isPersianLanguage(String? language) {
    if (language == null || language.isEmpty || language == 'Unknown') return false;
    final normalized = language.trim().toLowerCase().replaceAll('_', '-');
    final primary = normalized.split('-').first;
    if (_languageCodes.contains(primary)) return true;
    return normalized.contains('persian') ||
        normalized.contains('farsi') ||
        language.contains('فارسی');
  }

  /// True when the played item's primary (or any) audio track is Persian.
  static bool isPersianFilm(PlaybackModel? playbackModel) {
    return isPersianFilmFromStreams(playbackModel?.mediaStreams);
  }

  static bool isPersianFilmFromStreams(MediaStreamsModel? streams) {
    if (streams == null) return false;

    final audios = streams.audioStreams.where((stream) => stream.index != -1).toList();
    if (audios.isEmpty) return false;

    final defaultIndex = streams.defaultAudioStreamIndex;
    final defaultAudio = audios.firstWhere(
      (stream) => stream.index == defaultIndex,
      orElse: () => audios.first,
    );
    if (isPersianLanguage(defaultAudio.language) || isPersianLanguage(defaultAudio.displayTitle)) {
      return true;
    }

    for (final stream in audios) {
      if (isPersianLanguage(stream.language) || isPersianLanguage(stream.displayTitle)) {
        return true;
      }
    }

    for (final stream in streams.subStreams) {
      if (isPersianLanguage(stream.language) || isPersianLanguage(stream.displayTitle)) {
        return true;
      }
    }

    for (final stream in streams.versionStreams) {
      if (isPersianLanguage(stream.name)) return true;
    }

    return false;
  }

  static bool showIranFlagForSubtitle({
    required String? subtitleLanguage,
    PlaybackModel? playbackModel,
    MediaStreamsModel? mediaStreams,
    required int subtitleIndex,
  }) {
    if (subtitleIndex == -1) return false;
    if (isPersianLanguage(subtitleLanguage)) return true;
    if (isPersianFilm(playbackModel)) return true;
    return isPersianFilmFromStreams(mediaStreams);
  }
}
