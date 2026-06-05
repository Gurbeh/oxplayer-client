package app.oxplayer.player

import PlaybackState
import android.app.ActivityManager
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.view.WindowManager
import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.getSystemService
import androidx.core.os.postDelayed
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import android.util.Log
import io.github.peerless2012.ass.media.kt.buildWithAssSupport
import io.github.peerless2012.ass.media.type.AssRenderType
import kotlinx.coroutines.delay

import app.oxplayer.composables.overlays.guide.GuideOverlay
import app.oxplayer.composables.overlays.NextUpOverlay
import app.oxplayer.messengers.properlySetSubAndAudioTracks
import app.oxplayer.objects.PlayerSettingsObject
import app.oxplayer.objects.VideoPlayerObject
import app.oxplayer.utility.AllowedOrientations
import app.oxplayer.utility.conditional
import app.oxplayer.utility.getAudioTracks
import app.oxplayer.utility.getSubtitleTracks
import app.oxplayer.utility.toNativeMuxedAudioRow
import app.oxplayer.utility.toNativeMuxedSubtitleRow
import kotlin.time.Duration.Companion.seconds

private const val OX_NATIVE_PLY_TAG = "OX_NATIVE_PLY"

val LocalPlayer = compositionLocalOf<ExoPlayer?> { null }

@OptIn(UnstableApi::class)
@Composable
internal fun ExoPlayer(
    controls: @Composable (
        player: ExoPlayer,
    ) -> Unit,
) {
    val videoHost = VideoPlayerObject
    val context = LocalContext.current

    val extractorsFactory = DefaultExtractorsFactory().apply {
        val isLowRamDevice = context.getSystemService<ActivityManager>()?.isLowRamDevice == true
        setTsExtractorTimestampSearchBytes(
            when (isLowRamDevice) {
                true -> TsExtractor.TS_PACKET_SIZE * 1800
                false -> TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES
            }
        )
        setConstantBitrateSeekingEnabled(true)
        setConstantBitrateSeekingAlwaysEnabled(true)
    }

    val dataSourceFactory = remember {
        DefaultDataSource.Factory(context, DefaultHttpDataSource.Factory())
    }

    val audioAttributes = AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .build()

    val renderersFactory = DefaultRenderersFactory(context)
        .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        .setEnableDecoderFallback(true)

    val trackSelector = DefaultTrackSelector(context).apply {
        setParameters(buildUponParameters().apply {
            setAudioOffloadPreferences(
                TrackSelectionParameters.AudioOffloadPreferences.DEFAULT.buildUpon().apply {
                    setAudioOffloadMode(TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED)
                }.build()
            )
            setTunnelingEnabled(PlayerSettingsObject.settings.value?.enableTunneling ?: false)
            setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
        })
    }

    val exoPlayer = remember {
        ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory, extractorsFactory))
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setPauseAtEndOfMediaItems(true)
            .setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
            .buildWithAssSupport(
                context,
                renderersFactory = renderersFactory,
                extractorsFactory = extractorsFactory,
                renderType = AssRenderType.LEGACY
            )
    }

    fun updatePlaybackState() {
        videoHost.setPlaybackState(
            PlaybackState(
                position = exoPlayer.currentPosition,
                buffered = exoPlayer.bufferedPosition,
                duration = exoPlayer.duration,
                playing = exoPlayer.isPlaying,
                buffering = exoPlayer.playbackState == Player.STATE_BUFFERING,
                completed = exoPlayer.playbackState == Player.STATE_ENDED,
                failed = exoPlayer.playbackState == Player.STATE_IDLE
            )
        )
    }

    LaunchedEffect(exoPlayer) {
        while (true) {
            updatePlaybackState()
            delay(1.seconds)
        }
    }

    val activity = LocalActivity.current

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Log.e(
                    OX_NATIVE_PLY_TAG,
                    "onPlayerError code=${error.errorCode} name=${error.errorCodeName} " +
                        "msg=${error.message} cause=${error.cause?.message}",
                    error,
                )
                super.onPlayerError(error)
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                activity?.window?.let {
                    if (isPlaying) {
                        it.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        it.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
                super.onIsPlayingChanged(isPlaying)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                videoHost.setPlaybackState(
                    PlaybackState(
                        position = exoPlayer.currentPosition,
                        buffered = exoPlayer.bufferedPosition,
                        duration = exoPlayer.duration,
                        playing = exoPlayer.isPlaying,
                        buffering = playbackState == Player.STATE_BUFFERING,
                        completed = playbackState == Player.STATE_ENDED,
                        failed = playbackState == Player.STATE_IDLE
                    )
                )
            }

            override fun onEvents(player: Player, events: Player.Events) {
                super.onEvents(player, events)
                updatePlaybackState()
            }

            override fun onTracksChanged(tracks: Tracks) {
                super.onTracksChanged(tracks)
                val subTracks = exoPlayer.getSubtitleTracks()
                val audioTracks = exoPlayer.getAudioTracks()

                if (subTracks.isEmpty() && audioTracks.isEmpty()) return

                // Always publish Exo track lists so UI (e.g. hasSubtracks) matches the player.
                // Exo can fire onTracksChanged first with audio-only, then again when embedded
                // text tracks appear; the old logic set subsInitialized on the first callback and
                // never refreshed exoSubTracks, so subtitles stayed hidden until a later session.
                val hadNoExoSubtitleTracks = VideoPlayerObject.exoSubTracks.value.isEmpty()
                VideoPlayerObject.exoSubTracks.value = subTracks
                VideoPlayerObject.exoAudioTracks.value = audioTracks

                val impl = VideoPlayerObject.implementation
                // Short deferral: track groups must be mapped before overrides stick; a 1s
                // wait was unnecessarily slow and kept subtitles off until user interaction.
                val scheduleApplyDefaults: () -> Unit = {
                    val playbackData = impl.playbackData.value
                    Handler(Looper.getMainLooper()).postDelayed(delayInMillis = 150) {
                        playbackData?.let { exoPlayer.properlySetSubAndAudioTracks(it) }
                    }
                }

                if (!impl.subsInitialized) {
                    impl.subsInitialized = true
                    scheduleApplyDefaults()
                } else if (hadNoExoSubtitleTracks && subTracks.isNotEmpty()) {
                    // Late-mapped text tracks after the initial audio-only snapshot.
                    scheduleApplyDefaults()
                }

                notifyFlutterMuxedTrackDiscovery(exoPlayer)
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            exoPlayer.removeListener(listener)
        }
    }

    DisposableEffect(Unit) {
        VideoPlayerObject.implementation.init(exoPlayer)
        onDispose {
            videoHost.videoPlayerControls?.onStop(callback = {})
            VideoPlayerObject.implementation.playbackData.value = null
            VideoPlayerObject.tvGuide.value = null
            VideoPlayerObject.implementation.init(null)
            exoPlayer.release()
        }
    }

    val acceptedOrientations by PlayerSettingsObject.acceptedOrientations.collectAsState(emptyList())
    val fillScreen by PlayerSettingsObject.fillScreen.collectAsState(false)
    val videoFit by PlayerSettingsObject.videoFit.collectAsState(AspectRatioFrameLayout.RESIZE_MODE_FIT)

    val isTVPlayback by VideoPlayerObject.implementation.isTVMode.collectAsState(false)
    val nativeSubtitleSettings by PlayerSettingsObject.subtitleSettings.collectAsState(null)

    @Composable
    fun createPlayer(showControls: Boolean) {
        AndroidView(
            modifier = Modifier
                .fillMaxSize()
                .background(color = Color.Black)
                .conditional(!fillScreen) {
                    displayCutoutPadding()
                },
            factory = {
                PlayerView(it).apply {
                    player = exoPlayer
                    useController = false
                    resizeMode = videoFit
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    )
                    keepScreenOn = false
                    subtitleView?.apply {
                        setStyle(
                            CaptionStyleCompat(
                                android.graphics.Color.WHITE,
                                android.graphics.Color.TRANSPARENT,
                                android.graphics.Color.TRANSPARENT,
                                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                                android.graphics.Color.BLACK,
                                null
                            )
                        )
                    }
                }
            },
            update = { view ->
                nativeSubtitleSettings?.let { subtitleSettings ->
                    view.subtitleView?.apply {
                        setApplyEmbeddedFontSizes(false)

                        val frac =
                            (subtitleSettings.fontSize / 1080.0).toFloat().coerceIn(0.01f, 1f)
                        setFractionalTextSize(frac)

                        setBottomPaddingFraction(
                            subtitleSettings.verticalOffset.toFloat().coerceIn(0f, 0.5f)
                        )

                        setStyle(
                            CaptionStyleCompat(
                                subtitleSettings.color.toInt(),
                                subtitleSettings.backgroundColor.toInt(),
                                android.graphics.Color.TRANSPARENT,
                                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                                subtitleSettings.outlineColor.toInt(),
                                if (subtitleSettings.fontWeight >= 700) android.graphics.Typeface.DEFAULT_BOLD else android.graphics.Typeface.DEFAULT
                            )
                        )
                    }
                }
            },
        )
        if (showControls)
            CompositionLocalProvider(LocalPlayer provides exoPlayer) {
                controls(exoPlayer)
            }
    }

    AllowedOrientations(
        acceptedOrientations
    ) {
        when (isTVPlayback) {
            true -> GuideOverlay(
                modifier = Modifier.fillMaxSize(),
                overlay = {
                    createPlayer(showControls = it)
                }
            )

            false -> NextUpOverlay(
                modifier = Modifier
                    .fillMaxSize(),
                overlay = {
                    createPlayer(showControls = it)
                },
            )
        }
    }
}

private fun notifyFlutterMuxedTrackDiscovery(exoPlayer: ExoPlayer) {
    val listener = VideoPlayerObject.videoPlayerListener ?: return
    val audioTracks = exoPlayer.getAudioTracks()
    val subTracks = exoPlayer.getSubtitleTracks()
    if (audioTracks.isEmpty() && subTracks.isEmpty()) return
    val audioRows = audioTracks.map { it.toNativeMuxedAudioRow() }
    val subRows = subTracks.map { it.toNativeMuxedSubtitleRow() }
    listener.onMuxedTracksDiscovered(audioRows, subRows) { }
}
