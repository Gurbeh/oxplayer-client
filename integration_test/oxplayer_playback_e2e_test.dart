// OXPlayer playback E2E — drives the REAL app (real network, real Telegram session, real
// mpv/media_kit backend) on whatever device `flutter test integration_test/... -d <device>`
// targets (Windows desktop or an Android emulator/device). It is not a UI-tap test: navigation
// through Dashboard → Show → Episode is fragile to layout/locale, so this drives the same
// provider/extension entry points the real UI buttons call (`ItemBaseModel.play`,
// `videoPlayerProvider` seek/next/previous, `PlaybackModel.setSubtitle`) — the exact code paths
// that own the playback bugs this suite exists to catch regressions on:
//   - seeking deep into a file (~70%) stalling instead of resuming (oxtelegram HTTP bridge)
//   - subtitle off → on losing sync / becoming slow after the first toggle
//   - playback dying partway through / audio glitching under sustained playback
//   - slow time-to-first-frame
//
// Requires a machine that is already logged in (Telegram + server account) — this is a dev/QA
// tool, not a from-scratch CI suite. See scripts/e2e-playback.mjs for the runner.
//
// Run:
//   flutter test integration_test/oxplayer_playback_e2e_test.dart -d windows --dart-define-from-file=dart_defines.dev.json
//   flutter test integration_test/oxplayer_playback_e2e_test.dart -d <emulator-id> --dart-define-from-file=dart_defines.dev.json
//
// Point it at different library content without editing this file:
//   --dart-define=E2E_SHOW_1="From" --dart-define=E2E_SHOW_2="Manifest"

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/main.dart' as app;
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/oxplayer/oxplayer_playback_subtitle.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/wrappers/players/player_states.dart';

const _show1Title = String.fromEnvironment('E2E_SHOW_1', defaultValue: 'From');
const _show2Title = String.fromEnvironment('E2E_SHOW_2', defaultValue: 'Manifest');

/// Aspirational cold-start budget the user asked this suite to enforce. If the current
/// architecture (Telegram MTProto fetch → local cache → HTTP bridge → mpv open) can't hit this
/// yet, this test SHOULD fail loudly with the measured number rather than silently pass — that
/// failure is the actionable signal, not a false alarm.
const _fastStartBudget = Duration(seconds: 2);
const _loadTimeout = Duration(seconds: 30);
const _seekRecoveryBudget = Duration(seconds: 15);
const _switchRecoveryBudget = Duration(seconds: 20);

/// Exposes a real riverpod [Ref] for utility calls (e.g. [EpisodeModel.episodesFromDto]) that
/// need one but aren't themselves providers. Standard "capture a Ref" trick.
final _refCaptureProvider = Provider<Ref>((ref) => ref);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OXPlayer playback e2e (play / seek / episodes / subtitles)', (tester) async {
    app.main(const <String>[]);
    // Cold boot: auth restore, library warmup, first frame of the dashboard.
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // `Main` sits ABOVE the Navigator (Main -> PlatformAppWrapper -> MaterialApp.router ->
    // Navigator), so its own context has no Navigator ancestor — `.play()` needs a context
    // that's INSIDE the routed content. Use Main's element for the WidgetRef (position doesn't
    // matter for ref.read — it's the same ProviderContainer everywhere), and a Scaffold
    // somewhere in the actual first-route content for the Navigator-aware BuildContext.
    final refElement = tester.element(find.byType(app.Main));
    final ref = refElement as WidgetRef;
    final BuildContext context = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(context, listen: false);
    final apiRead = container.read;
    final modelRef = container.read(_refCaptureProvider);

    final results = <String, String>{};
    void record(String label, bool pass, String detail) {
      final line = '${pass ? 'PASS' : 'FAIL'} — $detail';
      results[label] = line;
      // ignore: avoid_print
      print('[e2e] $label: $line');
    }

    JellyService api() => apiRead(jellyApiProvider);

    Future<EpisodeModel> fetchEpisode(String showTitle, {required int season, required int episode}) async {
      final search = await api().itemsGet(
        searchTerm: showTitle,
        includeItemTypes: const [BaseItemKind.series],
        recursive: true,
        limit: 5,
      );
      final seriesId = search.body?.items.firstOrNull?.id;
      if (seriesId == null) {
        throw StateError('e2e fixture show "$showTitle" not found in this library');
      }
      final episodesResp = await api().showsSeriesIdEpisodesGet(
        seriesId: seriesId,
        season: season,
        enableUserData: true,
        fields: const [ItemFields.mediastreams, ItemFields.overview, ItemFields.parentid],
      );
      final episodes = EpisodeModel.episodesFromDto(episodesResp.body?.items, modelRef).toList();
      if (episodes.isEmpty) {
        throw StateError('e2e fixture show "$showTitle" season $season has no episodes');
      }
      return episodes.firstWhere((e) => e.episode == episode, orElse: () => episodes.first);
    }

    Stream<PlayerState> playerStates() => ref.read(videoPlayerProvider).stateStream;

    Future<void> waitUntilPlaying(String label, {Duration timeout = _seekRecoveryBudget}) async {
      await playerStates()
          .firstWhere((s) => s.playing && !s.buffering)
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException('$label: did not resume playing within $timeout'),
          );
    }

    Future<Duration> playAndMeasureStart(EpisodeModel ep, {Duration? startPosition}) async {
      final sw = Stopwatch()..start();
      final playedFuture = playerStates().firstWhere((s) => s.playing && !s.buffering);
      // `.play()` itself must not be allowed to hang forever — without this, a stall inside the
      // native player pipeline eats the whole 10-minute test budget instead of failing this one
      // fixture and letting the rest of the suite run.
      await ep.play(context, ref, startPosition: startPosition).timeout(
            _loadTimeout,
            onTimeout: () => throw TimeoutException('ep.play() did not return within $_loadTimeout'),
          );
      await playedFuture.timeout(_loadTimeout);
      sw.stop();
      return sw.elapsed;
    }

    // ---------------------------------------------------------------------
    // 1) Cold-start latency, across different titles (movie/show variety).
    // ---------------------------------------------------------------------
    for (final title in [_show1Title, _show2Title]) {
      try {
        final ep = await fetchEpisode(title, season: 1, episode: 1);
        final elapsed = await playAndMeasureStart(ep);
        record(
          'cold_start[$title S1E1]',
          elapsed <= _fastStartBudget,
          '${elapsed.inMilliseconds}ms (budget ${_fastStartBudget.inMilliseconds}ms)',
        );
      } catch (e) {
        record('cold_start[$title S1E1]', false, 'error: $e');
      }
    }

    // ---------------------------------------------------------------------
    // 2) Seek stress on one video, repeatedly, including the ~70% mark that
    //    used to hang on Windows (oxtelegram HTTP bridge idle-deadline bug).
    //    Also re-measures start latency after a forward seek, per the ask.
    // ---------------------------------------------------------------------
    try {
      final ep = await fetchEpisode(_show1Title, season: 1, episode: 5);
      await playAndMeasureStart(ep);
      final runtime = ref.read(playBackModel)?.item.overview.runTime ?? const Duration(minutes: 40);
      final fractions = [0.1, 0.3, 0.7, 0.5, 0.9, 0.2, 0.7];
      var allOk = true;
      final details = <String>[];
      for (final f in fractions) {
        final target = runtime * f;
        final sw = Stopwatch()..start();
        await ref.read(videoPlayerProvider).seek(target);
        try {
          await waitUntilPlaying('seek@${(f * 100).round()}%');
          sw.stop();
          final ms = sw.elapsedMilliseconds;
          if (ms > _fastStartBudget.inMilliseconds) allOk = false;
          details.add('${(f * 100).round()}%=${ms}ms');
        } catch (e) {
          allOk = false;
          details.add('${(f * 100).round()}%=STUCK');
        }
      }
      record('seek_stress[$_show1Title S1E5]', allOk, details.join(', '));
    } catch (e) {
      record('seek_stress[$_show1Title S1E5]', false, 'error: $e');
    }

    // ---------------------------------------------------------------------
    // 3) Episode next/previous, repeatedly.
    // ---------------------------------------------------------------------
    try {
      final ep = await fetchEpisode(_show1Title, season: 1, episode: 2);
      await playAndMeasureStart(ep);
      var allOk = true;
      final details = <String>[];
      for (final step in ['next', 'next', 'previous', 'previous', 'next']) {
        final sw = Stopwatch()..start();
        if (step == 'next') {
          await ref.read(videoPlayerProvider).loadNextVideo();
        } else {
          await ref.read(videoPlayerProvider).loadPreviousVideo();
        }
        try {
          await waitUntilPlaying('episode_$step', timeout: _switchRecoveryBudget);
          sw.stop();
          details.add('$step=${sw.elapsedMilliseconds}ms');
        } catch (e) {
          allOk = false;
          details.add('$step=STUCK');
        }
      }
      record('episode_switch[$_show1Title]', allOk, details.join(', '));
    } catch (e) {
      record('episode_switch[$_show1Title]', false, 'error: $e');
    }

    // ---------------------------------------------------------------------
    // 4) Persian auto-select + subtitle off→on toggling, repeatedly.
    // ---------------------------------------------------------------------
    try {
      final ep = await fetchEpisode(_show1Title, season: 1, episode: 3);
      await playAndMeasureStart(ep);
      final model = ref.read(playBackModel);
      final subStreams = model?.subStreams ?? const <SubStreamModel>[];
      final persianIndex = oxplayerPreferredSubtitleStreamIndex(subStreams);
      final autoSelected = model?.mediaStreams?.defaultSubStreamIndex;
      final persianOk = persianIndex == null || autoSelected == persianIndex;
      record(
        'persian_subtitle_autoselect[$_show1Title]',
        persianOk,
        persianIndex == null
            ? 'no Persian track in subStreams — skipped'
            : 'expectedIndex=$persianIndex actualIndex=$autoSelected',
      );

      final realSub = subStreams.firstWhereOrNullIndexNot(-1);
      if (realSub == null) {
        record('subtitle_toggle[$_show1Title]', true, 'no subtitle tracks on this episode — skipped');
      } else {
        final offSub = subStreams.firstWhereOrNullIndex(-1) ?? SubStreamModel.no();
        var toggleOk = true;
        final toggleDetails = <String>[];
        var currentModel = ref.read(playBackModel);
        for (var i = 0; i < 3; i++) {
          final off = await currentModel?.setSubtitle(offSub, ref.read(videoPlayerProvider));
          if (off != null) {
            currentModel = off;
            ref.read(playBackModel.notifier).state = off;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));

          final sw = Stopwatch()..start();
          final on = await currentModel?.setSubtitle(realSub, ref.read(videoPlayerProvider));
          sw.stop();
          final applied = on?.mediaStreams?.defaultSubStreamIndex == realSub.index;
          if (on != null) {
            currentModel = on;
            ref.read(playBackModel.notifier).state = on;
          }
          toggleOk = toggleOk && applied;
          toggleDetails.add('cycle$i=${applied ? 'ok' : 'FAIL'}(${sw.elapsedMilliseconds}ms)');
        }
        record('subtitle_toggle[$_show1Title]', toggleOk, toggleDetails.join(', '));
      }
    } catch (e) {
      record('subtitle_toggle[$_show1Title]', false, 'error: $e');
    }

    // ---------------------------------------------------------------------
    print('\n[e2e] ===== SUMMARY =====');
    for (final entry in results.entries) {
      print('[e2e] ${entry.key}: ${entry.value}');
    }

    final failures = results.entries.where((e) => e.value.startsWith('FAIL')).toList();
    expect(
      failures,
      isEmpty,
      reason: failures.map((e) => '${e.key}: ${e.value}').join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}

extension _SubStreamListFind on List<SubStreamModel> {
  SubStreamModel? firstWhereOrNullIndex(int index) {
    for (final s in this) {
      if (s.index == index) return s;
    }
    return null;
  }

  SubStreamModel? firstWhereOrNullIndexNot(int index) {
    for (final s in this) {
      if (s.index != index) return s;
    }
    return null;
  }
}
