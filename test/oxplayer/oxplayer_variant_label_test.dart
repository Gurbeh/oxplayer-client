import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_variant_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VersionStreamModel _stream({
  required String name,
  int height = 1080,
  bool hasSubs = false,
  String language = 'eng',
}) {
  return VersionStreamModel(
    name: name,
    index: 0,
    id: 'ms_0',
    defaultAudioStreamIndex: 1,
    defaultSubStreamIndex: hasSubs ? 2 : -1,
    videoStreams: [
      VideoStreamModel(
        name: '',
        codec: 'h264',
        isDefault: true,
        isExternal: false,
        index: 0,
        videoDoViTitle: null,
        videoRangeType: null,
        bitRate: null,
        width: height >= 1080 ? 1920 : 1280,
        height: height,
        frameRate: 24,
      ),
    ],
    audioStreams: [
      AudioStreamModel(
        displayTitle: language == 'fa' ? 'Persian' : 'English',
        name: '',
        codec: 'aac',
        isDefault: true,
        isExternal: false,
        index: 1,
        language: language,
        channelLayout: 'stereo',
        sampleRate: 48000,
        channels: 2,
        bitRate: null,
        bitDepth: null,
        profile: null,
        spatialFormat: null,
      ),
    ],
    subStreams: hasSubs
        ? [
            SubStreamModel(
              id: 'sub_0',
              title: 'Persian',
              displayTitle: 'Persian',
              name: '',
              codec: 'subrip',
              isDefault: false,
              isExternal: false,
              index: 2,
              language: 'fa',
            ),
          ]
        : const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppLocalizations> loadEn() => Future.value(lookupAppLocalizations(const Locale('en')));
  Future<AppLocalizations> loadFa() => Future.value(lookupAppLocalizations(const Locale('fa')));

  test('formats original english bluray in english locale', () async {
    final l10n = await loadEn();
    final label = oxplayerLocalizedVersionStreamLabel(
      l10n,
      _stream(name: '1080p - English - BluRay'),
    );
    expect(label, '1080p - English - BluRay');
  });

  test('formats dubbed persian in persian locale', () async {
    final l10n = await loadFa();
    final label = oxplayerLocalizedVersionStreamLabel(
      l10n,
      _stream(
        name: '1080p - dubbed (Persian) - WEB-DL',
        language: 'fa',
      ),
    );
    expect(label, '1080p - دوبله (فارسی) - WEB-DL');
  });

  test('formats soft sub without language suffix', () async {
    final l10n = await loadEn();
    final label = oxplayerLocalizedVersionStreamLabel(
      l10n,
      _stream(name: '720p - soft sub - PSA', height: 720, hasSubs: true),
    );
    expect(label, '720p - soft sub - PSA');
  });
}
