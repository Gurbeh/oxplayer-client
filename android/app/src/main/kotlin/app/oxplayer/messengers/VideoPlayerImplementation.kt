package app.oxplayer.messengers

import PlaybackState
import PlayableData
import SubtitleSettings
import TVGuideModel
import VideoPlayerApi
import android.net.Uri
import android.util.Log
import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import androidx.core.os.postDelayed
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import app.oxplayer.objects.PlayerSettingsObject
import app.oxplayer.objects.TdlibBridgeObject
import app.oxplayer.objects.VideoPlayerObject
import app.oxplayer.utility.clearAudioTrack
import app.oxplayer.utility.clearSubtitleTrack
import app.oxplayer.utility.enableSubtitles
import app.oxplayer.utility.getAudioTracks
import app.oxplayer.utility.getSubtitleTracks
import app.oxplayer.utility.isInternalSubtitleTrackSelected
import app.oxplayer.utility.isSubtitleTrackDisabled
import app.oxplayer.utility.setInternalAudioTrack
import app.oxplayer.utility.setInternalSubtitleTrack
import kotlin.time.Duration.Companion.seconds

private const val OX_NATIVE_PLY_TAG = "OX_NATIVE_PLY"
private const val OX_STREAM_TAG = "OX_STREAM"
private const val OX_AUDIO_TAG = "OX_AUDIO"

private fun oxAudioLog(message: String) {
    Log.i(OX_AUDIO_TAG, message)
    Log.d(OX_NATIVE_PLY_TAG, message)
}

private fun oxStreamLog(message: String) {
    Log.i(OX_STREAM_TAG, message)
    Log.d(OX_NATIVE_PLY_TAG, message)
}

/**
 * The synthetic playback-session id inside a Telegram-sourced url, or null for anything else.
 *
 * Both transports put it in the last path segment: `tdlib-file://{fileId}` (ExoPlayer's
 * OxRoutingDataSource) and `http://127.0.0.1:{port}/{fileId}` (TdlibHttpBridgeServer). The scheme
 * and host are checked first so an ordinary media/subtitle url that happens to end in digits is
 * never mistaken for a session handle.
 */
private fun telegramPlaybackFileId(url: String?): Int? {
    if (url.isNullOrBlank()) return null
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
    val isTelegramTransport = uri.scheme == "tdlib-file" ||
        (uri.host == "127.0.0.1" || uri.host == "localhost")
    if (!isTelegramTransport) return null
    return url.substringAfterLast('/').toIntOrNull()
}

private fun redactStreamUrl(url: String): String {
    val uri = Uri.parse(url)
    val path = uri.encodedPath ?: uri.path ?: ""
    return "${uri.scheme}://${uri.host}$path?…"
}

class VideoPlayerImplementation(
) : VideoPlayerApi {
    var player: ExoPlayer? = null
    val playbackData: MutableStateFlow<PlayableData?> = MutableStateFlow(null)

    var subsInitialized = false

    /** Last known position when the activity went to background (survives activity recreation). */
    var savedPositionMs: Long = 0L

    /** Whether playback was active when the activity went to background. */
    var wasPlayingBeforeBackground: Boolean = false

    private var playbackErrorListener: Player.Listener? = null

    private var initialPositionLogPosted = false

    private fun scheduleInitialPositionLog(exo: ExoPlayer, requestedStartMs: Long) {
        if (initialPositionLogPosted) return
        initialPositionLogPosted = true
        val checkpoints = longArrayOf(3_000L, 12_000L, 30_000L)
        for (delayMs in checkpoints) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (exo.mediaItemCount == 0) return@postDelayed
                val state = when (exo.playbackState) {
                    Player.STATE_IDLE -> "IDLE"
                    Player.STATE_BUFFERING -> "BUFFERING"
                    Player.STATE_READY -> "READY"
                    Player.STATE_ENDED -> "ENDED"
                    else -> "?"
                }
                oxStreamLog(
                    "phase=native_position_check delayMs=$delayMs state=$state " +
                        "requestedStartMs=$requestedStartMs actualMs=${exo.currentPosition} " +
                        "bufferedMs=${exo.bufferedPosition} durationMs=${exo.duration}",
                )
            }, delayMs)
        }
    }

    /** When [open] runs before ExoPlayer is bound, retry with this URL after [init]. */
    private var pendingOpenUrl: String? = null
    private var pendingOpenPlay: Boolean = true

    fun saveBackgroundState() {
        val exo = player ?: return
        val pos = exo.currentPosition.coerceAtLeast(0L)
        if (pos > 0L) {
            savedPositionMs = pos
            playbackData.value = playbackData.value?.copy(startPosition = pos)
        }
        wasPlayingBeforeBackground = exo.isPlaying || exo.playWhenReady
    }

    fun restoreAfterBackground() {
        val exo = player ?: return
        if (exo.mediaItemCount == 0) return

        val resumeMs = savedPositionMs
        if (resumeMs > 0L && kotlin.math.abs(exo.currentPosition - resumeMs) > 500L) {
            exo.seekTo(resumeMs)
        }
        if (wasPlayingBeforeBackground && !exo.isPlaying) {
            exo.play()
        }
        publishPlaybackState(exo)
    }

    fun clearSession() {
        // Read the url BEFORE clearing playbackData: it carries the fileId of the playback that is
        // ending, which is what TdlibBridgeObject must release. Handing it the "current" session id
        // instead would release whichever playback started most recently — and Dart resolves the
        // next play's url before tearing this one down, so that is routinely the wrong one.
        val endedFileId = telegramPlaybackFileId(playbackData.value?.url)
        playbackData.value = null
        savedPositionMs = 0L
        wasPlayingBeforeBackground = false
        pendingOpenUrl = null
        initialPositionLogPosted = false
        // No-op unless this session's video actually came from Telegram — see doc there.
        TdlibBridgeObject.onTelegramPlaybackEnded(endedFileId)
    }

    private fun publishPlaybackState(exo: ExoPlayer) {
        val hasMedia = exo.mediaItemCount > 0
        val state = exo.playbackState
        VideoPlayerObject.setPlaybackState(
            PlaybackState(
                position = exo.currentPosition,
                buffered = exo.bufferedPosition,
                duration = exo.duration,
                playing = exo.isPlaying,
                buffering = state == Player.STATE_BUFFERING,
                completed = state == Player.STATE_ENDED,
                failed = state == Player.STATE_IDLE && !hasMedia,
            ),
        )
    }

    val isTVMode: Flow<Boolean> = playbackData.asStateFlow().map {
        it?.mediaInfo?.playbackType == PlaybackType.TV
    }

    override fun sendPlayableModel(
        playableData: PlayableData,
        callback: (Result<Boolean>) -> Unit
    ) {
        try {
            Log.d(
                OX_NATIVE_PLY_TAG,
                "sendPlayableModel title=${playableData.currentItem?.title} id=${playableData.currentItem?.id} " +
                    "playbackType=${playableData.mediaInfo.playbackType} startMs=${playableData.startPosition} " +
                    "urlLen=${playableData.url.length} audioTracks=${playableData.audioTracks.size} " +
                    "subtitleTracks=${playableData.subtitleTracks.size}",
            )
            oxStreamLog(
                "phase=native_playable itemId=${playableData.currentItem?.id} " +
                    "startMs=${playableData.startPosition} " +
                    "host=${Uri.parse(playableData.url).host} " +
                    "url=${redactStreamUrl(playableData.url)}",
            )
            playbackData.value = playableData
            callback(Result.success(true))
            return
        } catch (e: Exception) {
            Log.e(OX_NATIVE_PLY_TAG, "sendPlayableModel failed", e)
            callback(Result.success(false))
            return
        }
    }

    override fun sendTVGuideModel(guide: TVGuideModel, callback: (Result<Boolean>) -> Unit) {
        try {
            VideoPlayerObject.tvGuide.value = guide
            callback(Result.success(true))
        } catch (e: Exception) {
            println("Error sending TV guide model: $e")
            callback(Result.success(false))
        }
    }

    override fun setSubtitleSettings(settings: SubtitleSettings) {
        try {
            PlayerSettingsObject.subtitleSettings.value = settings
        } catch (e: Exception) {
            println("Error setting subtitle settings: $e")
        }
    }

    override fun refreshDefaultTrackSelection(callback: (Result<Boolean>) -> Unit) {
        Handler(Looper.getMainLooper()).post {
            try {
                val data = playbackData.value
                val exo = player
                if (data == null || exo == null) {
                    callback(Result.success(false))
                    return@post
                }
                VideoPlayerObject.setAudioTrackIndex(data.defaultAudioTrack.toInt(), true)
                VideoPlayerObject.setSubtitleTrackIndex(data.defaultSubtrack.toInt(), true)
                exo.properlySetSubAndAudioTracks(data)
                callback(Result.success(true))
            } catch (e: Exception) {
                println("Error refreshDefaultTrackSelection $e")
                callback(Result.success(false))
            }
        }
    }

    override fun open(url: String, play: Boolean, callback: (Result<Boolean>) -> Unit) {
        Handler(Looper.getMainLooper()).postDelayed(delayInMillis = 1.seconds.inWholeMilliseconds) {
            try {
                val exo = player
                if (exo == null) {
                    Log.w(
                        OX_NATIVE_PLY_TAG,
                        "open defer: ExoPlayer not ready yet (will retry when host is bound)",
                    )
                    pendingOpenUrl = url
                    pendingOpenPlay = play
                    callback(Result.success(false))
                    return@postDelayed
                }
                pendingOpenUrl = null
                val pd = playbackData.value
                Log.d(
                    OX_NATIVE_PLY_TAG,
                    "open enter play=$play urlLen=${url.length} hasPlaybackData=${pd != null} " +
                        "exoPlayerNull=false",
                )
                pd?.let {
                    VideoPlayerObject.setAudioTrackIndex(it.defaultAudioTrack.toInt(), true)
                    VideoPlayerObject.setSubtitleTrackIndex(it.defaultSubtrack.toInt(), true)
                }

                val isHls = url.contains("streamMode=hls", ignoreCase = true) || url.endsWith(
                    ".m3u8",
                    ignoreCase = true
                )
                val subTitles = playbackData.value?.subtitleTracks ?: listOf()
                val externalSubs = subTitles.filter { it.external && !it.url.isNullOrEmpty() }
                Log.d(
                    OX_NATIVE_PLY_TAG,
                    "open building MediaItem isHls=$isHls externalSubtitleCount=${externalSubs.size} " +
                        "startPositionMs=${playbackData.value?.startPosition ?: 0L}",
                )
                val mediaItemBuilder = MediaItem.Builder()
                    .setUri(url)
                    .setTag(playbackData.value?.currentItem?.title)
                    .setMediaId(playbackData.value?.currentItem?.id ?: "")
                    .setSubtitleConfigurations(
                        subTitles.filter { it.external && !it.url.isNullOrEmpty() }.map { sub ->
                            MediaItem.SubtitleConfiguration.Builder(sub.url!!.toUri())
                                .setMimeType(guessSubtitleMimeType(sub.url))
                                .setLanguage(sub.languageCode)
                                .setLabel(sub.name)
                                .build()
                        }
                    )

                if (isHls) {
                    mediaItemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
                }

                val mediaItem = mediaItemBuilder.build()

                val startPosition = (playbackData.value?.startPosition ?: 0L).coerceAtLeast(0L)

                exo.stop()
                exo.clearMediaItems()

                exo.setMediaItem(mediaItem, startPosition)
                exo.prepare()
                exo.playWhenReady = play
                oxStreamLog(
                    "phase=native_open startMs=$startPosition " +
                        "host=${Uri.parse(url).host} isHls=$isHls url=${redactStreamUrl(url)}",
                )
                Log.d(OX_NATIVE_PLY_TAG, "open prepared playWhenReady=$play startPositionMs=$startPosition")
                callback(Result.success(true))
                subsInitialized = false
                scheduleInitialPositionLog(exo, startPosition)
                return@postDelayed
            } catch (e: Exception) {
                Log.e(OX_NATIVE_PLY_TAG, "open exception", e)
                callback(Result.success(false))
                return@postDelayed
            }
        }
    }

    override fun setLooping(looping: Boolean) {
        player?.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    override fun setVolume(volume: Double) {
        val exo = player
        val applied = volume.toFloat().coerceIn(0f, 1f)
        oxAudioLog(
            "phase=audio_set_volume requested=$volume applied=$applied exoNull=${exo == null}",
        )
        exo?.volume = applied
    }

    override fun setPlaybackSpeed(speed: Double) {
        player?.setPlaybackSpeed(speed.toFloat())
    }

    override fun play() {
        player?.play()
    }

    override fun pause() {
        player?.pause()
    }

    override fun seekTo(position: Long) {
        player?.seekTo(position)
    }

    override fun stop() {
        player?.stop()
        player?.clearMediaItems()
        clearSession()
    }

    fun init(exoPlayer: ExoPlayer?) {
        playbackErrorListener?.let { player?.removeListener(it) }
        playbackErrorListener = null
        player = exoPlayer
        subsInitialized = false
        if (exoPlayer == null) {
            pendingOpenUrl = null
            return
        }
        val errorListener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Log.e(
                    OX_NATIVE_PLY_TAG,
                    "onPlayerError code=${error.errorCode} name=${error.errorCodeName} " +
                        "msg=${error.message} cause=${error.cause?.message}",
                    error,
                )
                VideoPlayerObject.reportPlaybackError(error)
            }
        }
        playbackErrorListener = errorListener
        exoPlayer.addListener(errorListener)
        val deferredUrl = pendingOpenUrl
        val deferredPlay = pendingOpenPlay
        if (!deferredUrl.isNullOrBlank()) {
            pendingOpenUrl = null
            Log.d(OX_NATIVE_PLY_TAG, "init applying deferred open urlLen=${deferredUrl.length} play=$deferredPlay")
            open(deferredUrl, deferredPlay, callback = {})
            return
        }
        playbackData.value?.let { playData ->
            if (exoPlayer.mediaItemCount > 0) {
                restoreAfterBackground()
                return
            }
            val resumeMs = savedPositionMs.takeIf { it > 0L } ?: playData.startPosition
            val updated = playData.copy(startPosition = resumeMs)
            playbackData.value = updated
            VideoPlayerObject.setAudioTrackIndex(updated.defaultAudioTrack.toInt(), true)
            VideoPlayerObject.setSubtitleTrackIndex(updated.defaultSubtrack.toInt(), true)
            val shouldPlay = wasPlayingBeforeBackground
            Log.d(
                OX_NATIVE_PLY_TAG,
                "init restoring after recreation resumeMs=$resumeMs play=$shouldPlay",
            )
            open(updated.url, shouldPlay, callback = {})
        }
    }

    /** Only clears the binding when the releasing instance is still current (activity switch race). */
    fun releasePlayer(exoPlayer: ExoPlayer): Boolean {
        if (player !== exoPlayer) return false
        playbackErrorListener?.let { exoPlayer.removeListener(it) }
        playbackErrorListener = null
        player = null
        subsInitialized = false
        return true
    }
}

fun guessSubtitleMimeType(fileName: String): String = when {
    fileName.contains(".srt", ignoreCase = true) -> MimeTypes.APPLICATION_SUBRIP
    fileName.contains(".vtt", ignoreCase = true) -> MimeTypes.TEXT_VTT
    fileName.contains(".ass", ignoreCase = true) -> MimeTypes.TEXT_SSA
    else -> MimeTypes.APPLICATION_SUBRIP
}

fun ExoPlayer.properlySetSubAndAudioTracks(playableData: PlayableData) {
    if (playableData.mediaInfo.playbackType == PlaybackType.TV) {
        // In TV mode, do not set tracks here as they are handled differently
        return
    }
    val exo = this
    try {
        // User picks in native UI update current*Index + playbackData; prefer that over stale defaults.
        val currentSubIndex = VideoPlayerObject.currentSubtitleTrackIndex.value.toLong()
        val internalSubTracks = this.getSubtitleTracks()
        val listPos = playableData.subtitleTracks.indexOfFirst { it.index == currentSubIndex }
        val wantedSubIndex: Int = when {
            listPos >= 0 -> listPos - 1
            currentSubIndex > 0 &&
                internalSubTracks.isNotEmpty() &&
                listPos < 0 -> {
                0
            }
            else -> listPos - 1
        }

        if (wantedSubIndex < 0) {
            if (!exo.isSubtitleTrackDisabled()) {
                clearSubtitleTrack()
            }
        } else if (wantedSubIndex >= internalSubTracks.size) {
            // Exo text tracks not mapped yet; a later onTracksChanged will schedule again.
        } else {
            val subTrack = internalSubTracks[wantedSubIndex]
            if (!exo.isInternalSubtitleTrackSelected(subTrack)) {
                clearSubtitleTrack()
                Handler(Looper.getMainLooper()).post {
                    try {
                        exo.setInternalSubtitleTrack(subTrack)
                    } catch (_: Exception) {
                    }
                }
            }
        }

        val currentAudioIndex = VideoPlayerObject.currentAudioTrackIndex.value.toLong()
        val indexOfAudioTrack =
            playableData.audioTracks.indexOfFirst { it.index == currentAudioIndex }
        val internalAudioTracks = this.getAudioTracks()

        val wantedAudioIndex = indexOfAudioTrack - 1
        // playableData.audioTracks[0] is the Jellyfin "Off" row; real streams start at index 1.
        fun serverIndexForInternal(internalIdx: Int) {
            playableData.audioTracks.getOrNull(internalIdx + 1)?.index?.let {
                VideoPlayerObject.setAudioTrackIndex(it.toInt(), true)
            }
        }
        val action = when {
            internalAudioTracks.isEmpty() -> "clear_empty_exo_tracks"
            currentAudioIndex < 0 -> "disable_audio_negative_index"
            wantedAudioIndex < 0 -> "fallback_first_exo_track"
            wantedAudioIndex >= internalAudioTracks.size -> "fallback_last_exo_track"
            else -> "select_mapped_exo_track"
        }
        oxAudioLog(
            "phase=audio_track_apply action=$action currentAudioIndex=$currentAudioIndex " +
                "wantedAudioIndex=$wantedAudioIndex exoAudioCount=${internalAudioTracks.size} " +
                "pigeonAudioCount=${playableData.audioTracks.size} defaultAudio=${playableData.defaultAudioTrack} " +
                "exoCodecs=${internalAudioTracks.joinToString { it.codec ?: "?" }}",
        )
        if (internalAudioTracks.isEmpty()) {
            clearAudioTrack()
        } else if (currentAudioIndex < 0) {
            clearAudioTrack(disable = true)
        } else if (wantedAudioIndex < 0) {
            // Jellyfin stream index not in pigeon list — fall back to first mapped Exo track.
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[0])
            serverIndexForInternal(0)
        } else if (wantedAudioIndex >= internalAudioTracks.size) {
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[internalAudioTracks.lastIndex])
            serverIndexForInternal(internalAudioTracks.lastIndex)
        } else {
            clearAudioTrack(false)
            setInternalAudioTrack(internalAudioTracks[wantedAudioIndex])
            serverIndexForInternal(wantedAudioIndex)
        }
    } catch (e: Exception) {
        e.printStackTrace()
    }
}
