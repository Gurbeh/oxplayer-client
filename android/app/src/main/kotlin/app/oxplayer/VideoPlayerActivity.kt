package app.oxplayer

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.annotation.OptIn
import androidx.annotation.RequiresApi
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.util.UnstableApi
import app.oxplayer.composables.controls.CustomVideoControls
import app.oxplayer.composables.overlays.screensavers.ScreenSaver
import app.oxplayer.objects.VideoPlayerObject
import app.oxplayer.player.ExoPlayer
import app.oxplayer.utility.ScaledContent
import app.oxplayer.utility.leanBackEnabled

class VideoPlayerActivity : ComponentActivity() {
    private var isInPip = false

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        VideoPlayerObject.currentActivity = this

        window.setFlags(
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
        )

        window.setFormat(PixelFormat.TRANSLUCENT)

        setContent {
            VideoPlayerTheme {
                VideoPlayerScreen()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isInPip = false
        VideoPlayerObject.implementation.restoreAfterBackground()
    }

    override fun onPause() {
        // Skip pausing playback when entering/already in PiP so the mini window
        // keeps playing while the user is in another app.
        if (!isInPip) {
            VideoPlayerObject.implementation.saveBackgroundState()
            super.onPause()
            VideoPlayerObject.implementation.pause()
        } else {
            super.onPause()
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            tryEnterPip()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPip = isInPictureInPictureMode
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun tryEnterPip() {
        val exo = VideoPlayerObject.implementation.player ?: return
        // Only auto-enter PiP when there is media loaded and actively playing.
        if (exo.mediaItemCount == 0) return
        if (!exo.isPlaying && !exo.playWhenReady) return

        val vs = exo.videoSize
        val w = if (vs.width > 0) vs.width else 16
        val h = if (vs.height > 0) vs.height else 9
        // Android requires PiP aspect ratio in [0.418410, 2.39] (1/2.39 .. 2.39).
        val ratio = w.toFloat() / h.toFloat()
        val clamped = when {
            ratio > 2.39f -> Rational(239, 100)
            ratio < 1f / 2.39f -> Rational(100, 239)
            else -> Rational(w, h)
        }
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(clamped)
            .build()
        try {
            enterPictureInPictureMode(params)
        } catch (_: IllegalStateException) {
            // Activity not in foreground / PiP not allowed at this moment; ignore.
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (VideoPlayerObject.currentActivity === this) {
            VideoPlayerObject.currentActivity = null
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
fun VideoPlayerScreen(
) {
    val leanBackEnabled = leanBackEnabled(LocalContext.current)
    ScreenSaver {
        ExoPlayer { player ->
            ScaledContent(
                scale = if (leanBackEnabled) 0.75f else 1f,
                fontScale = if (leanBackEnabled) 1.2f else 1f,
            ) {
                CustomVideoControls(player)
            }
        }
    }
}
