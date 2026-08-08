package app.oxplayer

import BatteryOptimizationPigeon
import NativeVideoActivity
import OxTdlibBridgeApi
import PlayerSettingsPigeon
import StartResult
import TranslationsPigeon
import VideoPlayerApi
import VideoPlayerControlsCallback
import VideoPlayerListenerCallback
import android.annotation.SuppressLint
import android.content.Intent
import android.os.Bundle
import android.os.PowerManager
import android.net.Uri
import android.util.Log
import android.provider.Settings
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.LocalContext
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import app.oxplayer.objects.PlayerSettingsObject
import app.oxplayer.objects.TdlibBridgeObject
import app.oxplayer.objects.TranslationsMessenger
import app.oxplayer.objects.VideoPlayerObject
import app.oxplayer.utility.leanBackEnabled
import androidx.core.net.toUri

class MainActivity : AudioServiceFragmentActivity(), NativeVideoActivity {

    private lateinit var videoPlayerLauncher: ActivityResultLauncher<Intent>
    private var videoPlayerCallback: ((Result<StartResult>) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ enforces edge-to-edge for SDK 35+ targets; enableEdgeToEdge()
        // is the backward-compatible way to opt in across all supported API levels.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val videoPlayerHost = VideoPlayerObject
        NativeVideoActivity.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            this
        )
        VideoPlayerApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            videoPlayerHost.implementation
        )
        videoPlayerHost.videoPlayerListener =
            VideoPlayerListenerCallback(flutterEngine.dartExecutor.binaryMessenger)

        videoPlayerHost.videoPlayerControls =
            VideoPlayerControlsCallback(flutterEngine.dartExecutor.binaryMessenger)

        TranslationsMessenger.translation =
            TranslationsPigeon(flutterEngine.dartExecutor.binaryMessenger)

        PlayerSettingsPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = PlayerSettingsObject
        )

        TdlibBridgeObject.attach(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        OxTdlibBridgeApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = TdlibBridgeObject,
        )

        BatteryOptimizationPigeon.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            api = object : BatteryOptimizationPigeon {
                override fun isIgnoringBatteryOptimizations(): Boolean {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    return pm.isIgnoringBatteryOptimizations(packageName)
                }

                override fun openBatteryOptimizationSettings() {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }
        )

        videoPlayerLauncher = registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            val callback = videoPlayerCallback
            videoPlayerCallback = null

            val startResult = if (result.resultCode == RESULT_OK) {
                StartResult(resultValue = result.data?.getStringExtra("result") ?: "Finished")
            } else {
                StartResult(resultValue = "Cancelled")
            }

                VideoPlayerObject.implementation.player?.stop()
                VideoPlayerObject.implementation.player?.release()
                // Null-out the player before the Dart callback so that any subsequent
                // Dart-side stop() call goes through VideoPlayerImplementation.stop()
                // safely (player?.stop() becomes a null-safe no-op on a released player).
                VideoPlayerObject.implementation.init(null)
                VideoPlayerObject.implementation.clearSession()
                VideoPlayerObject.tvGuide.value = null
                callback?.invoke(Result.success(startResult))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Ensure the Activity's intent is updated so Flutter (and plugins / AutoRoute) receive runtime deep-links.
        setIntent(intent)
    }

    override fun launchActivity(callback: (Result<StartResult>) -> Unit) {
        try {
            videoPlayerCallback = callback
            val intent = Intent(this, VideoPlayerActivity::class.java)
            videoPlayerLauncher.launch(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            callback(Result.failure(e))
        }
    }

    override fun disposeActivity() {
        VideoPlayerObject.implementation.stop()
        VideoPlayerObject.tvGuide.value = null
        VideoPlayerObject.currentActivity?.finish()
    }

    override fun isLeanBackEnabled(): Boolean = leanBackEnabled(applicationContext)
}
