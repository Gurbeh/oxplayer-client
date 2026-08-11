import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_playback_subtitle.dart';

SubStreamModel _sub({
  required int index,
  required String language,
  String displayTitle = '',
}) {
  return SubStreamModel(
    name: displayTitle,
    id: '$index',
    title: displayTitle,
    displayTitle: displayTitle.isEmpty ? language : displayTitle,
    language: language,
    codec: 'subrip',
    isDefault: false,
    isExternal: false,
    index: index,
  );
}

void main() {
  test('hardsub media source defaults subtitle Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: 2,
        subStreams: streams,
        mediaSourceName: '1080p - hard sub (Persian)',
      ),
      -1,
    );
  });

  test('softsub still prefers Persian when no selection', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'eng', displayTitle: 'English'),
      _sub(index: 3, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: null,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      3,
    );
  });

  test('server Off is respected (no forced Persian)', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: null,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p - soft sub',
      ),
      -1,
    );
  });

  test('explicit user selection wins over hardsub Off', () {
    final streams = [
      SubStreamModel.no(),
      _sub(index: 2, language: 'fa', displayTitle: 'Persian'),
    ];
    expect(
      oxplayerResolveSubtitleStreamIndex(
        selectedIndex: 2,
        serverDefaultIndex: -1,
        subStreams: streams,
        mediaSourceName: '1080p HardSub',
      ),
      2,
    );
  });
}
