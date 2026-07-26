import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:fladder/oxplayer/playback/ox_hls_web_buffer_config.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/subtitle_settings_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/oxplayer/oxplayer_iran_stream_edge.dart';
import 'package:fladder/oxplayer/oxplayer_env.dart';
import 'package:fladder/oxplayer/oxplayer_playback_repair.dart';
import 'package:fladder/oxplayer/oxplayer_playback_telemetry.dart';
import 'package:fladder/oxplayer/oxplayer_stream_url_resolver.dart';
import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/oxplayer_stream_mpv.dart';
import 'package:fladder/oxplayer/oxplayer_audio_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_log.dart';
import 'package:fladder/oxplayer/oxplayer_stream_http_auth.dart';
import 'package:fladder/oxplayer/playback/ox_subtitle_font.dart';
import 'package:fladder/providers/settings/subtitle_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/video_player.dart' as video_screen;
import 'package:fladder/util/subtitle_position_calculator.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

class LibMPV extends BasePlayer {
  mpv.Player? _player;
  VideoController? _controller;
  String _currentSubtitleCodec = '';
  String _currentSubtitleLanguage = '';
  SubtitleSettingsModel? _subtitleSettings;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  StreamSubscription<bool>? _onCompleted;

  bool _replayGainFallbackLogged = false;
  VideoPlayerSettingsModel _settings = VideoPlayerSettingsModel();

  RestartableTimer? _retryTimer;
  DateTime _firstLoadAttempt = DateTime.now();
  final Duration _maxRetryDuration = const Duration(minutes: 1);
  final Duration _currentRetryDuration = const Duration(seconds: 5);
  Completer<void>? _loadCompleter;
  final List<StreamSubscription> _playerStreamSubs = [];
  double _preferredVolume = 100;
  int _fadeGeneration = 0;
  bool _isFading = false;
  bool _subtitleTextSeen = false;
  int _externalSubtitleLoadGen = 0;

  void _logAudio(String phase, {Map<String, Object?> fields = const {}}) {
    OxplayerAudioLog.event(phase, fields: {
      'backend': 'mpv',
      'preferredVolume': _preferredVolume,
      'playerVolume': _player?.state.volume,
      'isFading': _isFading,
      'fadeGen': _fadeGeneration,
      'playPauseFade': _settings.enablePlayPauseFade,
      'replayGain': _settings.enableReplayGain,
      ...fields,
    });
  }

  void _reportVolumeAnomaly(
    String reason, {
    required double playerVolume,
    required double preferredVolume,
    bool fadeAborted = false,
  }) {
    if (!OxplayerEnv.isEnabled) return;
    unawaited(OxplayerPlaybackTelemetry.reportVolumeAnomaly(
      reason: reason,
      playerVolume: playerVolume,
      preferredVolume: preferredVolume,
      enablePlayPauseFade: _settings.enablePlayPauseFade,
      fadeAborted: fadeAborted,
    ));
  }

  /// Absolute timeline offset for ox-stream remux (stream starts at ?start= but UI uses catalog clock).
  Duration _remuxTimelineBase = Duration.zero;
  Duration get playPauseFadeDuration => const Duration(milliseconds: 175);

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _settings = settings;
    dispose();

    mpv.MediaKit.ensureInitialized();
    await OxHlsWebBufferConfig.apply();

    _player = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        title: "nl.jknaapen.fladder",
        libassAndroidFont: OxSubtitleFont.libassFontForPlayer,
        libass: !kIsWeb && settings.useLibass,
        bufferSize: settings.bufferSize * 1024 * 1024, // MPV uses buffer size in bytes
      ),
    );

    if (_player != null) {
      _controller = VideoController(
        _player!,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: settings.hardwareAccel,
        ),
      );
      _setupPlayerStreams(_player!);
    }

    if (_player?.platform is mpv.NativePlayer) {
      final nativePlayer = _player!.platform as dynamic;
      await nativePlayer.setProperty('force-seekable', 'yes');
      await nativePlayer.setProperty('gapless-audio', 'weak');

      if (defaultTargetPlatform == TargetPlatform.android) {
        // Use audiotrack as it is generally more stable on modern Android
        await nativePlayer.setProperty('ao', 'audiotrack');
      }
      _logAudio('mpv_init', fields: {
        'ao': defaultTargetPlatform == TargetPlatform.android ? 'audiotrack' : 'default',
        'hardwareAccel': settings.hardwareAccel,
      });
    }

    await _applyReplayGainSettings();
    _logAudio('mpv_replaygain_applied');
  }

  @override
  Future<void> dispose() async {
    _remuxTimelineBase = Duration.zero;
    _fadeGeneration++;
    _cancelPlayerStreams();
    _onCompleted?.cancel();
    _onCompleted = null;
    _player?.stop();
    _player?.dispose();
    _player = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _subtitleTextSeen = false;
    _externalSubtitleLoadGen++;
  }

  void setState(PlayerState state) {
    if (_remuxTimelineBase > Duration.zero) {
      if (state.position < _remuxTimelineBase - const Duration(seconds: 30)) {
        state = state.update(position: state.position + _remuxTimelineBase);
      }
    }
    lastState = state;
    _stateController.add(state);
  }

  void _cancelPlayerStreams() {
    for (final sub in _playerStreamSubs) {
      sub.cancel();
    }
    _playerStreamSubs.clear();
  }

  void _setupPlayerStreams(mpv.Player player) {
    _playerStreamSubs.addAll([
      player.stream.playing.listen((value) {
        if (value && _player?.state.volume == 0 && _preferredVolume > 0) {
          _logAudio('volume_restore_on_play', fields: {'reason': 'playing_event'});
          _reportVolumeAnomaly(
            'volume_restored_on_play_event',
            playerVolume: 0,
            preferredVolume: _preferredVolume,
          );
          _player?.setVolume(_preferredVolume);
        }
        setState(lastState.update(playing: value));
      }),
      player.stream.buffering.listen((value) => setState(lastState.update(buffering: value))),
      player.stream.position.listen((value) => setState(lastState.update(position: value))),
      player.stream.duration.listen((value) {
        if (_remuxTimelineBase > Duration.zero) return;
        setState(lastState.update(duration: value));
      }),
      player.stream.volume.listen((value) {
        if (!_isFading) {
          final clamped = value.clamp(0.0, 100.0);
          final paused = !player.state.playing;
          if (clamped == 0 && paused && _preferredVolume > 0) {
            _logAudio('volume_zero_while_paused', fields: {'playerVolume': clamped});
            _reportVolumeAnomaly(
              'preferred_volume_zeroed_while_paused',
              playerVolume: clamped,
              preferredVolume: _preferredVolume,
            );
            setState(lastState.update(volume: clamped));
            return;
          }
          _preferredVolume = clamped;
          setState(lastState.update(volume: clamped));
        }
      }),
      player.stream.subtitle.listen((value) {
        if (value.any((line) => line.trim().isNotEmpty)) {
          if (!_subtitleTextSeen) {
            _subtitleTextSeen = true;
            OxplayerStreamLog.event('subtitle_text_seen', fields: {
              'preview': () {
                final line = value.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
                return line.length > 40 ? '${line.substring(0, 40)}…' : line;
              }(),
            });
          }
        }
      }),
      player.stream.rate.listen((value) => setState(lastState.update(rate: value))),
      player.stream.buffer.listen((value) => setState(lastState.update(buffer: value))),
      player.stream.completed.listen((value) => setState(lastState.update(completed: value))),
    ]);
  }

  Future<void> crossfadeToUrl(String url, Duration startPosition, {double? replayGainDb}) async {
    if (!_settings.enableCrossfade || !VideoPlayerSettingsModel.crossfadeSupportedOnCurrentPlatform) {
      await _applyReplayGainSettings(trackGainDb: replayGainDb);
      await loadVideo(url, true, startPosition: startPosition);
      return;
    }

    final oldPlayer = _player;
    if (oldPlayer == null) {
      await loadVideo(url, true, startPosition: startPosition);
      return;
    }

    const stepMs = 16;
    final steps = math.max(1, _settings.crossfadeDurationMs ~/ stepMs);

    final incomingPlayer = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        title: "nl.jknaapen.fladder",
        libassAndroidFont: OxSubtitleFont.libassFontForPlayer,
        libass: !kIsWeb && _settings.useLibass,
        bufferSize: _settings.bufferSize * 1024 * 1024,
      ),
    );

    if (incomingPlayer.platform is mpv.NativePlayer) {
      final native = incomingPlayer.platform as dynamic;
      await native.setProperty('force-seekable', 'yes');
      await native.setProperty('gapless-audio', 'weak');
      if (defaultTargetPlatform == TargetPlatform.android) {
        await native.setProperty('ao', 'audiotrack');
      }
      await native.setProperty('start', '${startPosition.inMilliseconds / 1000}');
    }

    await _applyReplayGainSettings(trackGainDb: replayGainDb, targetPlayer: incomingPlayer);
    await incomingPlayer.setVolume(0.0);
    await incomingPlayer.open(mpv.Media(url), play: true);

    final generation = ++_fadeGeneration;
    _isFading = true;
    final fromVolume = oldPlayer.state.volume.clamp(0.0, 100.0);

    bool aborted = false;
    for (var i = 1; i <= steps; i++) {
      if (generation != _fadeGeneration) {
        aborted = true;
        break;
      }
      final progress = i / steps;
      await oldPlayer.setVolume(fromVolume * (1.0 - progress));
      await incomingPlayer.setVolume(_preferredVolume * progress);
      if (i < steps) await Future.delayed(const Duration(milliseconds: stepMs));
    }

    if (aborted || generation != _fadeGeneration) {
      _isFading = false;
      incomingPlayer.stop();
      incomingPlayer.dispose();
      return;
    }

    _cancelPlayerStreams();
    _player = incomingPlayer;
    _controller = null;
    _setupPlayerStreams(incomingPlayer);

    _retryTimer?.cancel();
    _retryTimer = null;
    _loadCompleter = null;

    oldPlayer.stop();
    oldPlayer.dispose();

    _isFading = false;
    setState(lastState.update(
      playing: incomingPlayer.state.playing,
      buffering: incomingPlayer.state.buffering,
      position: incomingPlayer.state.position,
      duration: incomingPlayer.state.duration,
      volume: _preferredVolume,
      buffer: incomingPlayer.state.buffer,
      completed: false,
    ));
  }

  /// ox-stream progressive remux (MPEG-TS); duration stays 0 on web until enough is buffered.
  static bool _isOxStreamRemuxUrl(String url) => url.contains('/stream.ts') || url.contains('stream.ts?');

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    _loadCompleter = Completer<void>();
    _firstLoadAttempt = DateTime.now();
    _subtitleTextSeen = false;
    _externalSubtitleLoadGen++;

    final isOxStreamTs = _isOxStreamRemuxUrl(url);
    // Progressive ox-stream TS: long-lived HTTP read — no 5s reopen on web or Android mpv.
    final progressiveOxStream = isOxStreamTs;
    final oxStreamDirectMkv = oxplayerStreamDirectMkvUrl(url);
    final oxStreamResumeSeek = oxplayerStreamMpvResumeSeekGrace(url, startPosition);
    final serverSeek = isOxStreamTs && url.contains('start=');
    _remuxTimelineBase = serverSeek ? startPosition : Duration.zero;

    if (oxStreamResumeSeek) {
      OxplayerStreamLog.event('mpv_resume_grace', fields: {
        'startPosition': OxplayerStreamLog.formatDuration(startPosition),
        'retryIntervalSec': oxplayerStreamMpvResumeRetryInterval.inSeconds,
        'maxRetrySec': oxplayerStreamMpvResumeMaxRetry.inSeconds,
      });
    }

    await setStartPosition(serverSeek ? Duration.zero : startPosition);

    if (OxplayerEnv.isEnabled && oxplayerIsOxStreamUrl(url)) {
      if (OxplayerIranStreamEdge.isIranVanityStreamUrl(url)) {
        url = await OxplayerIranStreamEdge.resolvePlaybackUrl(url);
      }
      if (kIsWeb) {
        url = OxplayerIranStreamEdge.rewriteWebPlaybackUrl(url);
      }
    }

    url = OxplayerStreamHttpAuth.stripAndRegister(url);

    // OX stream: always send Worker client signature; optional Bearer when enabled.
    if (OxplayerEnv.isEnabled && oxplayerIsOxStreamUrl(url) && _player?.platform is mpv.NativePlayer) {
      final bearer = OxplayerStreamHttpAuth.needsHeaderAuthForUrl(url)
          ? OxplayerStreamHttpAuth.bearerFor(url)
          : null;
      await (_player?.platform as dynamic).setProperty(
        'http-header-fields',
        OxplayerStreamHttpAuth.mpvHttpHeaderFields(bearer: bearer),
      );
      if (OxplayerStreamHttpAuth.needsHeaderAuthForUrl(url)) {
        if (bearer != null && bearer.isNotEmpty) {
          OxplayerStreamLog.event('stream_header_auth', fields: {
            'host': OxplayerStreamLog.describeHost(url),
          });
        } else {
          OxplayerStreamLog.event('stream_header_auth_missing', fields: {
            'host': OxplayerStreamLog.describeHost(url),
            'hasBearer': false,
            'nativeMpv': true,
          });
        }
      }
    }

    await _player?.open(mpv.Media(url), play: play);
    final openedVolume = _player?.state.volume ?? -1;
    if (_preferredVolume > 0 && openedVolume <= 0.5) {
      _logAudio('load_open_volume_fix', fields: {
        'openedVolume': openedVolume,
        'play': play,
        'urlHost': OxplayerStreamLog.describeHost(url),
      });
      await _player?.setVolume(_preferredVolume);
    } else {
      _logAudio('load_open', fields: {
        'openedVolume': openedVolume,
        'play': play,
        'urlHost': OxplayerStreamLog.describeHost(url),
      });
    }

    _retryTimer?.cancel();
    _retryTimer = null;

    // Progressive remux is a long-lived HTTP read; reopening every 5s kills ffmpeg mid-pipe.
    if (!progressiveOxStream) {
      final retryEvery =
          oxStreamResumeSeek ? oxplayerStreamMpvResumeRetryInterval : _currentRetryDuration;
      final maxRetry = oxStreamResumeSeek ? oxplayerStreamMpvResumeMaxRetry : _maxRetryDuration;
      _retryTimer = RestartableTimer(
        retryEvery,
        () async {
          await Future.delayed(const Duration(milliseconds: 150));
          if (DateTime.now().isAfter(_firstLoadAttempt.add(maxRetry))) {
            log("Max retry duration reached, stopping retries.");
            if (OxplayerEnv.isEnabled && oxplayerIsOxStreamUrl(url)) {
              final bridgeRef = OxplayerStreamRepairBridge.ref;
              final failoverUrl = bridgeRef != null
                  ? await oxplayerFailoverStreamUrl(bridgeRef.read, url)
                  : null;
              if (failoverUrl != null && failoverUrl != url) {
                log("Failover ox-stream to alternate node");
                _firstLoadAttempt = DateTime.now();
                await setStartPosition(startPosition);
                await _player?.open(mpv.Media(failoverUrl), play: play);
                _retryTimer?.reset();
                return;
              }
              final repairedUrl = await oxplayerTryRepairStreamUrl(url);
              if (repairedUrl != null) {
                log("Retrying ox-stream with force-repair URL");
                _firstLoadAttempt = DateTime.now();
                await setStartPosition(startPosition);
                await _player?.open(mpv.Media(repairedUrl), play: play);
                _retryTimer?.reset();
                return;
              }
            }
            unawaited(OxplayerPlaybackTelemetry.reportFailure(
              stage: 'player_load',
              reason: 'max_retry_duration_reached',
              streamUrl: url,
              transient: await _deviceAppearsOffline(),
            ));
            _retryTimer?.cancel();
            _retryTimer = null;
          } else {
            if (OxplayerEnv.isEnabled && oxplayerIsOxStreamUrl(url)) {
              final bridgeRef = OxplayerStreamRepairBridge.ref;
              final failoverUrl = bridgeRef != null
                  ? await oxplayerFailoverStreamUrl(bridgeRef.read, url)
                  : null;
              if (failoverUrl != null && failoverUrl != url) {
                log("Failover ox-stream to alternate node (retry)");
                _firstLoadAttempt = DateTime.now();
                await setStartPosition(startPosition);
                await _player?.open(mpv.Media(failoverUrl), play: play);
                _retryTimer?.reset();
                return;
              }
            }
            log("Retrying to load video $url");
            await setStartPosition(startPosition);
            await _player?.open(mpv.Media(url), play: play);
            _retryTimer?.reset();
          }
        },
      );
    }

    // Wait for the player to be ready
    if (_loadCompleter?.isCompleted == false) {
      StreamSubscription? subBuffering;
      StreamSubscription? subDuration;
      StreamSubscription? subPlaying;
      Timer? remuxReadyTimeout;

      void onReady() {
        if (_loadCompleter?.isCompleted == true) return;
        remuxReadyTimeout?.cancel();
        _finishedLoading();
        subBuffering?.cancel();
        subDuration?.cancel();
        subPlaying?.cancel();
      }

      if (progressiveOxStream || oxStreamDirectMkv) {
        subPlaying = _player?.stream.playing.listen((event) {
          if (event) {
            if ((serverSeek || oxStreamDirectMkv) && startPosition > Duration.zero) {
              setState(lastState.update(position: startPosition, buffering: false));
            }
            onReady();
          }
        });
        final readyTimeout = oxStreamResumeSeek
            ? oxplayerStreamMpvResumeReadyTimeout
            : oxplayerStreamMpvDefaultReadyTimeout;
        remuxReadyTimeout = Timer(readyTimeout, onReady);

        // A reload (audio switch / seek) re-opens the element after an async PlaybackInfo
        // call, so the browser drops the user-gesture and won't auto-resume. Nudge play a
        // few times until the stream actually starts.
        if (play) {
          for (final delayMs in [200, 600, 1500]) {
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_player != null && _player?.state.playing != true) {
                _player?.play();
              }
            });
          }
        }
      }

      subBuffering = _player?.stream.buffering.listen((event) {
        if (event == false) {
          final dur = _player?.state.duration ?? Duration.zero;
          if (dur > Duration.zero || oxStreamDirectMkv) {
            onReady();
          }
        }
      });
      subDuration = _player?.stream.duration.listen((event) {
        if (event > Duration.zero) onReady();
      });
    }

    _loadCompleter?.future.then(
      (value) async {
        // Remux URL already includes ?start= from PlaybackInfo; do not seek again on web.
        if (serverSeek) return;
        if (startPosition != Duration.zero && (_player?.state.position.inSeconds ?? 0) < startPosition.inSeconds - 5) {
          await _player?.seek(startPosition);
        }
      },
    );
    return setState(lastState.update(buffering: true));
  }

  /// Apply ReplayGain normalization for the given [item] before loading it.
  /// Call this before [loadVideo] when starting an audio queue item.
  Future<void> applyReplayGainForItem(ItemBaseModel? item) async {
    double? gainDb;
    if (item is AudioModel) {
      final gain = item.normalizationGain;
      if (gain != null && !gain.isNaN && !gain.isInfinite) {
        gainDb = gain.clamp(-60.0, 20.0).toDouble();
      }
    }
    await _applyReplayGainSettings(trackGainDb: gainDb);
  }

  double get _replayGainVolumeOffsetDb {
    return _settings.replayGainVolumeLevel.replayGainOffsetDb;
  }

  Future<void> _applyReplayGainSettings({double? trackGainDb, mpv.Player? targetPlayer}) async {
    final player = targetPlayer ?? _player;
    if (player?.platform is! mpv.NativePlayer) {
      return;
    }

    final nativePlayer = player!.platform as dynamic;

    if (!_settings.enableReplayGain) {
      try {
        await nativePlayer.setProperty('af', '');
      } catch (_) {
        // Best effort clear.
      }
      return;
    }

    final replayGainOffsetDb = clampReplayGainDb(_replayGainVolumeOffsetDb);
    final replayGainFallbackDb = _settings.replayGainVolumeLevel.adjustedReplayGainDb(trackGainDb);

    try {
      await nativePlayer.setProperty('replaygain', 'track');
      await nativePlayer.setProperty('replaygain-clip', 'yes');
      await nativePlayer.setProperty('replaygain-fallback', '$replayGainFallbackDb');
      await nativePlayer.setProperty('replaygain-preamp', '$replayGainOffsetDb');
      await nativePlayer.setProperty('af', '');
      _replayGainFallbackLogged = false;
    } catch (error, stackTrace) {
      if (!_replayGainFallbackLogged) {
        log('ReplayGain unsupported by current mpv backend, falling back to loudnorm. $error\n$stackTrace');
      }
      _replayGainFallbackLogged = true;

      try {
        final gainFilter = ',volume=${replayGainFallbackDb}dB';
        await nativePlayer.setProperty('af', 'format=stereo,loudnorm$gainFilter');
      } catch (fallbackError, fallbackStackTrace) {
        log('Unable to set loudnorm fallback filter. $fallbackError\n$fallbackStackTrace');
      }
    }
  }

  Future<void> setStartPosition(Duration position) async {
    if (_player?.platform is mpv.NativePlayer) {
      await (_player?.platform as dynamic).setProperty(
        'start',
        '${position.inMilliseconds / 1000}',
      );
    }
  }

  void _finishedLoading() {
    _loadCompleter?.complete();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// OX: fetch Jellyfin DeliveryUrl in background — prod API ffmpeg-extracts full SRT (30–90s).
  /// Never await on playback path (was blocking video for 45s+).
  Future<void> _loadExternalSubtitleInBackground(SubStreamModel wanted, int loadGen) async {
    final url = wanted.url;
    if (url == null || url.isEmpty || _player == null) return;

    await _configureMpvForTextSubtitle(wanted.codec);

    if (OxplayerConfig.isEnabled) {
      OxplayerStreamLog.event('subtitle_track_external_start', fields: {
        'url': OxplayerStreamLog.describeUrl(url),
        'index': wanted.index,
      });
    }

    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
      if (loadGen != _externalSubtitleLoadGen || _player == null) return;
      if (response.statusCode != 200) {
        OxplayerStreamLog.event('subtitle_track_external_fail', fields: {
          'status': response.statusCode,
          'index': wanted.index,
        });
        return;
      }
      final text = response.body.trim();
      if (text.isEmpty || loadGen != _externalSubtitleLoadGen || _player == null) return;

      await _player!.setSubtitleTrack(
        mpv.SubtitleTrack.data(
          text,
          title: wanted.displayTitle,
          language: wanted.language,
        ),
      );
      await _syncLibassSubtitleStyle();
      OxplayerStreamLog.event('subtitle_track_external', fields: {
        'url': OxplayerStreamLog.describeUrl(url),
        'index': wanted.index,
        'bytes': text.length,
        'via': 'data',
      });
    } catch (error) {
      if (loadGen != _externalSubtitleLoadGen) return;
      OxplayerStreamLog.event('subtitle_track_external_fail', fields: {
        'index': wanted.index,
        'error': error.runtimeType.toString(),
      });
    }
  }

  bool _isAssSubtitleCodec(String codec) {
    final c = codec.toLowerCase();
    return c.contains('ass') || c.contains('ssa');
  }

  /// SRT/VTT need Flutter overlay via sub-text; libass sub-ass=yes blocks that on Android.
  Future<void> _configureMpvForTextSubtitle(String codec) async {
    if (_player?.platform is! mpv.NativePlayer || !_settings.useLibass) return;
    if (_isAssSubtitleCodec(codec)) return;
    final native = _player!.platform as dynamic;
    try {
      await native.setProperty('sub-ass', 'no');
      await native.setProperty('sub-visibility', 'yes');
    } catch (_) {}
  }

  @override
  Future<void> open(BuildContext context) async => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (context) => const video_screen.VideoPlayer(),
        ),
      );

  List<mpv.SubtitleTrack> get subTracks => _player?.state.tracks.subtitle ?? [];
  mpv.SubtitleTrack get subtitleTrack => _player?.state.track.subtitle ?? mpv.SubtitleTrack.no();

  List<mpv.AudioTrack> get audioTracks => _player?.state.tracks.audio ?? [];
  mpv.AudioTrack get audioTrack => _player?.state.track.audio ?? mpv.AudioTrack.no();

  Future<void> _fadePlayback(bool fadingIn) async {
    final player = _player;
    if (player == null) return;

    if (!_settings.enablePlayPauseFade) {
      if (fadingIn) {
        await player.play();
      } else {
        await player.pause();
      }
      return;
    }

    if (fadingIn && _preferredVolume > 0 && (player.state.volume - _preferredVolume).abs() < 1) {
      _logAudio('fade_skip_already_at_target');
      await player.play();
      return;
    }

    _logAudio(fadingIn ? 'fade_in_start' : 'fade_out_start', fields: {
      'from': fadingIn ? 0.0 : player.state.volume,
      'to': fadingIn ? _preferredVolume : 0.0,
    });

    final generation = ++_fadeGeneration;
    _isFading = true;
    final from = fadingIn ? 0.0 : player.state.volume.clamp(0.0, 100.0);
    final to = fadingIn ? _preferredVolume : 0.0;
    const stepMs = 16;
    final steps = playPauseFadeDuration.inMilliseconds ~/ stepMs;

    if (fadingIn) {
      await player.play();
      await player.setVolume(from);
    }

    for (var i = 1; i <= steps; i++) {
      if (generation != _fadeGeneration || _player == null) {
        _isFading = false;
        if (fadingIn && player.state.playing && player.state.volume <= 0.5 && _preferredVolume > 0) {
          _logAudio('fade_aborted_restore', fields: {'playerVolume': player.state.volume});
          _reportVolumeAnomaly(
            'play_fade_aborted_while_muted',
            playerVolume: player.state.volume,
            preferredVolume: _preferredVolume,
            fadeAborted: true,
          );
          await player.setVolume(_preferredVolume);
        }
        return;
      }
      await player.setVolume(from + (to - from) * i / steps);
      if (i < steps) await Future.delayed(const Duration(milliseconds: stepMs));
    }

    if (!fadingIn && generation == _fadeGeneration && _player != null) {
      _fadeGeneration++;
      await player.pause();
    }
    _isFading = false;
    if (fadingIn && generation == _fadeGeneration && player.state.volume <= 0.5 && _preferredVolume > 0) {
      _logAudio('fade_done_still_muted_restore', fields: {'playerVolume': player.state.volume});
      _reportVolumeAnomaly(
        'stuck_muted_after_play_fade',
        playerVolume: player.state.volume,
        preferredVolume: _preferredVolume,
      );
      await player.setVolume(_preferredVolume);
    }
    setState(lastState.update(volume: _preferredVolume));
  }

  @override
  Future<void> pause() async => _fadePlayback(false);

  @override
  Future<void> play() async => _fadePlayback(true);

  @override
  Future<void> playOrPause() async {
    if ((_player?.state.playing ?? lastState.playing) == true) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async => _player?.seek(position);

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    final wantedAudioStream = model ?? playbackModel.defaultAudioStream;
    if (wantedAudioStream == null) return -1;
    if (wantedAudioStream.index == AudioStreamModel.no().index) {
      final muxedAvailable = playbackModel.audioStreams?.any((s) => s.index >= 0) ?? false;
      if (OxplayerConfig.isEnabled && !playbackModel.isAudioPlayback && muxedAvailable) {
        _logAudio('audio_track_skip_off_muxed', fields: {
          'defaultAudioIndex': playbackModel.mediaStreams?.defaultAudioStreamIndex,
        });
        return -1;
      }
      _logAudio('audio_track_off');
      await _player?.setAudioTrack(mpv.AudioTrack.no());
    } else {
      final internalTracks = audioTracks.getRange(2, audioTracks.length).toList();
      final listIndex = (playbackModel.audioStreams?.indexOf(wantedAudioStream) ?? -1) - 1;
      final audioTrack = internalTracks.elementAtOrNull(listIndex);
      _logAudio('audio_track_select', fields: {
        'wantedIndex': wantedAudioStream.index,
        'wantedCodec': wantedAudioStream.codec,
        'listIndex': listIndex,
        'mpvTrackCount': internalTracks.length,
        'applied': audioTrack != null,
      });
      if (audioTrack != null) {
        await _player?.setAudioTrack(audioTrack);
      }
    }
    return wantedAudioStream.index;
  }

  @override
  Future<void> setSpeed(double speed) async => _player?.setRate(speed);

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (_player == null) return -1;
    final wantedSubtitle = model ?? playbackModel.defaultSubStream;
    if (wantedSubtitle == null || wantedSubtitle.index == SubStreamModel.no().index) {
      _currentSubtitleCodec = '';
      _currentSubtitleLanguage = '';
      await _player?.setSubtitleTrack(mpv.SubtitleTrack.no());
      await _syncLibassSubtitleStyle();
      return -1;
    }
    _currentSubtitleCodec = wantedSubtitle.codec;
    _currentSubtitleLanguage = wantedSubtitle.language;
    _subtitleTextSeen = false;
    _externalSubtitleLoadGen++;

    await _configureMpvForTextSubtitle(wantedSubtitle.codec);

    // Fladder: jellyfin sub stream index → mpv demux list (skips auto/no).
    final internalTracks =
        subTracks.length > 2 ? subTracks.getRange(2, subTracks.length).toList() : <mpv.SubtitleTrack>[];
    final sublistIndex = playbackModel.subStreams?.sublist(1).indexWhere((e) => e.id == wantedSubtitle.id);
    final subTrack = internalTracks.elementAtOrNull(sublistIndex ?? -1);

    final url = wantedSubtitle.url;
    final hasUrl = url != null && url.isNotEmpty;
    final useExternalUri =
        hasUrl && (wantedSubtitle.isExternal || wantedSubtitle.supportsExternalStream);

    // OX: DeliveryUrl before demux — progressive CDN MKV can expose ghost embedded
    // tracks (sid set but no dialogue); external SRT from API is the reliable path.
    if (useExternalUri) {
      final loadGen = _externalSubtitleLoadGen;
      unawaited(_loadExternalSubtitleInBackground(wantedSubtitle, loadGen));
    } else if (subTrack != null) {
      await _player?.setSubtitleTrack(subTrack);
    } else if (wantedSubtitle.index >= 0 && !wantedSubtitle.isExternal) {
      await _player!.setSubtitleTrack(
        mpv.SubtitleTrack(
          wantedSubtitle.index.toString(),
          wantedSubtitle.displayTitle,
          wantedSubtitle.language,
          codec: wantedSubtitle.codec,
        ),
      );
      if (OxplayerConfig.isEnabled) {
        OxplayerStreamLog.event('subtitle_track_direct_sid', fields: {
          'sid': wantedSubtitle.index,
          'codec': wantedSubtitle.codec,
        });
      }
    }

    await _syncLibassSubtitleStyle();
    return wantedSubtitle.index;
  }

  @override
  void applySubtitleSettings(SubtitleSettingsModel settings) {
    _subtitleSettings = settings;
    unawaited(_syncLibassSubtitleStyle());
  }

  Future<void> _syncLibassSubtitleStyle() async {
    if (!OxplayerConfig.isEnabled || _player?.platform is! mpv.NativePlayer) return;
    final native = _player!.platform as dynamic;
    final hasSubtitle = _currentSubtitleCodec.isNotEmpty || _currentSubtitleLanguage.isNotEmpty;
    final settings = _subtitleSettings;
    try {
      if (!hasSubtitle || settings == null) {
        await native.setProperty('sub-ass-override', 'no');
        await native.setProperty('sub-ass-force-style', '');
        return;
      }
      if (!_isAssSubtitleCodec(_currentSubtitleCodec)) {
        await native.setProperty('sub-ass', 'no');
        await native.setProperty('sub-visibility', 'yes');
        return;
      }
      await native.setProperty('sub-ass-override', 'force');
      await native.setProperty(
        'sub-ass-force-style',
        OxSubtitleFont.assForceStyle(settings, language: _currentSubtitleLanguage),
      );
    } catch (_) {}
  }

  @override
  Future<void> addToPlaylist(String url) async => _player?.add(mpv.Media(url));

  @override
  Future<void> removeFromPlaylist(int index) async => _player?.remove(index);

  @override
  Future<void> playerNext() async => _player?.next();

  @override
  Future<void> playerPrevious() async => _player?.previous();

  @override
  Stream<int> get playlistIndexStream => _player?.stream.playlist.map((p) => p.index) ?? const Stream<int>.empty();

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<Uint8List?> takeScreenshot() async {
    return _player?.screenshot(format: "image/png", includeLibassSubtitles: true);
  }

  @override
  Widget? videoWidget(
    Key key,
    BoxFit fit,
  ) =>
      _controller == null
          ? null
          : Video(
              key: key,
              controller: _controller!,
              wakelock: false,
              fill: Colors.transparent,
              fit: fit,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              controls: NoVideoControls,
            );

  @override
  Widget? subtitles(
    bool showOverlay, {
    GlobalKey? controlsKey,
  }) =>
      _controller != null
          ? _VideoSubtitles(
              controller: _controller!,
              showOverlay: showOverlay,
              controlsKey: controlsKey,
              currentSubtitleCodec: _currentSubtitleCodec,
              currentSubtitleLanguage: _currentSubtitleLanguage,
            )
          : null;

  @override
  Future<void> setVolume(double volume) async {
    _isFading = false;
    _preferredVolume = volume.clamp(0.0, 100.0);
    _fadeGeneration++;
    _logAudio('set_volume', fields: {'requested': volume, 'applied': _preferredVolume});
    await _player?.setVolume(_preferredVolume);
  }

  @override
  Future<void> loop(bool loop) async {
    if (loop && _onCompleted == null) {
      _onCompleted = _player?.stream.completed.listen((completed) {
        if (completed) {
          _player?.play();
        }
      });
    } else {
      _onCompleted?.cancel();
    }
  }
}

class _VideoSubtitles extends ConsumerStatefulWidget {
  final VideoController controller;
  final bool showOverlay;
  final GlobalKey? controlsKey;
  final String currentSubtitleCodec;
  final String currentSubtitleLanguage;

  const _VideoSubtitles({
    required this.controller,
    this.showOverlay = false,
    this.controlsKey,
    this.currentSubtitleCodec = '',
    this.currentSubtitleLanguage = '',
  });

  @override
  _VideoSubtitlesState createState() => _VideoSubtitlesState();
}

class _VideoSubtitlesState extends ConsumerState<_VideoSubtitles> {
  late List<String> subtitle;
  String _cachedSubtitleText = '';
  List<String>? _lastSubtitleList;
  StreamSubscription<List<String>>? subscription;

  double? _cachedMenuHeight;

  @override
  void initState() {
    super.initState();
    subtitle = widget.controller.player.state.subtitle;
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      if (mounted) {
        setState(() {
          subtitle = value;
          _lastSubtitleList = null;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measureMenuHeight();

    final settings = ref.watch(subtitleSettingsProvider);
    final padding = MediaQuery.paddingOf(context);

    if (!const ListEquality().equals(subtitle, _lastSubtitleList)) {
      _lastSubtitleList = List<String>.from(subtitle);
      _cachedSubtitleText = subtitle.where((line) => line.trim().isNotEmpty).map((line) => line.trim()).join('\n');
    }

    final text = _cachedSubtitleText;

    final playbackSubLanguage = ref.watch(
      playBackModel.select((model) => model?.mediaStreams?.currentSubStream?.language),
    );
    final subtitleLanguage = widget.currentSubtitleLanguage.isNotEmpty
        ? widget.currentSubtitleLanguage
        : playbackSubLanguage;

    final bool isLibassEnabled = widget.controller.player.platform?.configuration.libass ?? false;

    if (isLibassEnabled) {
      // On desktop (Linux/Windows/macOS), mpv burns ALL subtitle formats into the video when libass is enabled.
      // On mobile (Android/iOS), only ASS/SSA subs are burned in by libass; other formats need the Flutter overlay.
      final bool isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS;
      if (isDesktop) {
        return const SizedBox.shrink();
      }
      final currentSubCodec = widget.currentSubtitleCodec.toLowerCase();
      final bool isAssSubtitle = currentSubCodec.contains('ass') || currentSubCodec.contains('ssa');
      if (isAssSubtitle || text.isEmpty) {
        return const SizedBox.shrink();
      }
    } else if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final offset = SubtitlePositionCalculator.calculateOffset(
      settings: settings,
      showOverlay: widget.showOverlay,
      screenHeight: MediaQuery.sizeOf(context).height,
      menuHeight: _cachedMenuHeight,
    );

    return SubtitleText(
      subModel: settings,
      padding: padding,
      offset: offset,
      text: text,
      subtitleLanguage: subtitleLanguage,
    );
  }

  void _measureMenuHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controlsKey == null) return;

      final RenderBox? renderBox = widget.controlsKey?.currentContext?.findRenderObject() as RenderBox?;
      final newHeight = renderBox?.size.height;

      if (newHeight != _cachedMenuHeight && newHeight != null) {
        setState(() {
          _cachedMenuHeight = newHeight;
        });
      }
    });
  }
}

Future<bool> _deviceAppearsOffline() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.isEmpty || results.every((r) => r == ConnectivityResult.none);
  } catch (_) {
    return false;
  }
}
