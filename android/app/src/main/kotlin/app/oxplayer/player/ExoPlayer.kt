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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.getSystemService
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
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
import app.oxplayer.utility.leanBackEnabled
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
    val activityManager = context.getSystemService<ActivityManager>()
    val isLowRamDevice = activityManager?.isLowRamDevice == true
    val isLeanBackTv = leanBackEnabled(context)
    val conserveMemory = isLowRamDevice || isLeanBackTv

    val extractorsFactory = DefaultExtractorsFactory().apply {
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
        // Must match Cloudflare stream Worker X-OX-Client-Signature gate
        // (oxplayer-client OxplayerStreamHttpAuth.clientSignatureValue).
        val httpFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(
                mapOf("X-OX-Client-Signature" to "YourSuperSecureStaticClientKey123"),
            )
        DefaultDataSource.Factory(context, httpFactory)
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
            if (!conserveMemory) {
                setAudioOffloadPreferences(
                    TrackSelectionParameters.AudioOffloadPreferences.DEFAULT.buildUpon().apply {
                        setAudioOffloadMode(TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED)
                    }.build()
                )
            }
            setTunnelingEnabled(PlayerSettingsObject.settings.value?.enableTunneling ?: false)
            setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
        })
    }

    val loadControl = if (conserveMemory) {
        DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                15_000,
                45_000,
                1_500,
                3_000,
            )
            .setTargetBufferBytes(16 * 1024 * 1024)
            .build()
    } else {
        DefaultLoadControl.Builder().build()
    }

    val trackApplyHandler = remember { Handler(Looper.getMainLooper()) }
    var pendingTrackApply by remember { mutableStateOf<Runnable?>(null) }

    val exoPlayer = remember {
        ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
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
        val hasMedia = exoPlayer.mediaItemCount > 0
        val state = exoPlayer.playbackState
        videoHost.setPlaybackState(
            PlaybackState(
                position = exoPlayer.currentPosition,
                buffered = exoPlayer.bufferedPosition,
                duration = exoPlayer.duration,
                playing = exoPlayer.isPlaying,
                buffering = state == Player.STATE_BUFFERING,
                completed = state == Player.STATE_ENDED,
                failed = state == Player.STATE_IDLE && !hasMedia,
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
                VideoPlayerObject.reportPlaybackError(error)
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
                val hasMedia = exoPlayer.mediaItemCount > 0
                videoHost.setPlaybackState(
                    PlaybackState(
                        position = exoPlayer.currentPosition,
                        buffered = exoPlayer.bufferedPosition,
                        duration = exoPlayer.duration,
                        playing = exoPlayer.isPlaying,
                        buffering = playbackState == Player.STATE_BUFFERING,
                        completed = playbackState == Player.STATE_ENDED,
                        failed = playbackState == Player.STATE_IDLE && !hasMedia,
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

                Log.i(
                    "OX_AUDIO",
                    "phase=audio_tracks_changed exoAudio=${audioTracks.size} exoSub=${subTracks.size} " +
                        "exoVolume=${exoPlayer.volume} playing=${exoPlayer.isPlaying} " +
                        "audioCodecs=${audioTracks.joinToString { it.codec ?: "?" }}",
                )

                if (subTracks.isEmpty() && audioTracks.isEmpty()) return

                // Always publish Exo track lists so UI (e.g. hasSubtracks) matches the player.
                // Exo can fire onTracksChanged first with audio-only, then again when embedded
                // text tracks appear; the old logic set subsInitialized on the first callback and
                // never refreshed exoSubTracks, so subtitles stayed hidden until a later session.
                val hadNoExoAudioTracks = VideoPlayerObject.exoAudioTracks.value.isEmpty()
                val hadNoExoSubtitleTracks = VideoPlayerObject.exoSubTracks.value.isEmpty()
                VideoPlayerObject.exoSubTracks.value = subTracks
                VideoPlayerObject.exoAudioTracks.value = audioTracks

                val impl = VideoPlayerObject.implementation
                // Short deferral: track groups must be mapped before overrides stick; debounce
                // so rapid onTracksChanged bursts (e.g. after TV Home resume) coalesce to one apply.
                val scheduleApplyDefaults: () -> Unit = scheduleApplyDefaults@{
                    val playbackData = impl.playbackData.value ?: return@scheduleApplyDefaults
                    pendingTrackApply?.let { trackApplyHandler.removeCallbacks(it) }
                    val runnable = Runnable {
                        pendingTrackApply = null
                        exoPlayer.properlySetSubAndAudioTracks(playbackData)
                    }
                    pendingTrackApply = runnable
                    trackApplyHandler.postDelayed(runnable, 150)
                }

                if (!impl.subsInitialized) {
                    impl.subsInitialized = true
                    scheduleApplyDefaults()
                } else if ((hadNoExoSubtitleTracks && subTracks.isNotEmpty()) ||
                    (hadNoExoAudioTracks && audioTracks.isNotEmpty())
                ) {
                    // Late-mapped text or audio tracks after the initial snapshot.
                    scheduleApplyDefaults()
                }
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            pendingTrackApply?.let { trackApplyHandler.removeCallbacks(it) }
            pendingTrackApply = null
            exoPlayer.removeListener(listener)
        }
    }

    DisposableEffect(Unit) {
        VideoPlayerObject.implementation.init(exoPlayer)
        onDispose {
            val finishing = activity?.isFinishing == true
            if (finishing) {
                videoHost.videoPlayerControls?.onStop(callback = {})
                if (VideoPlayerObject.implementation.releasePlayer(exoPlayer)) {
                    VideoPlayerObject.implementation.clearSession()
                    VideoPlayerObject.tvGuide.value = null
                }
            } else {
                // Activity recreated (e.g. TV home) — keep session data for restore in init().
                VideoPlayerObject.implementation.saveBackgroundState()
                VideoPlayerObject.implementation.releasePlayer(exoPlayer)
            }
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
        var playerView by remember { mutableStateOf<PlayerView?>(null) }
        val lifecycleOwner = LocalLifecycleOwner.current

        DisposableEffect(lifecycleOwner, playerView) {
            val view = playerView
            if (view == null) {
                onDispose { }
            } else {
                val observer = LifecycleEventObserver { _, event ->
                    when (event) {
                        Lifecycle.Event.ON_RESUME -> view.onResume()
                        Lifecycle.Event.ON_PAUSE -> view.onPause()
                        else -> Unit
                    }
                }
                lifecycleOwner.lifecycle.addObserver(observer)
                onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
            }
        }

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
                    playerView = this
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

