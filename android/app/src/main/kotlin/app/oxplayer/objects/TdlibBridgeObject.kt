package app.oxplayer.objects

import android.util.Log
import OxTdlibAuthState
import OxTdlibAuthStateKind
import OxTdlibBridgeApi
import OxTdlibBridgeEvents
import OxTdlibPlaybackSource
import android.content.Context
import android.os.Handler
import android.os.Looper
import app.oxplayer.tdlibbridge.auth.OxTelegramAuthController
import app.oxplayer.tdlibbridge.auth.TdlibAuthState
import app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher
import app.oxplayer.tdlibbridge.player.OxTelegramStreamBridge
import app.oxplayer.tdlibbridge.player.TdlibHttpBridgeServer
import app.oxplayer.tdlibbridge.session.OxTelegramClient
import app.oxplayer.tdlibbridge.session.OxTelegramSessionStorage
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger

/**
 * Singleton bridging Flutter (OxTdlibBridgeApi, Pigeon-generated) to ox_tdlib_bridge's Kotlin
 * classes, mirroring this app's PlayerSettingsObject/VideoPlayerObject convention of an object
 * implementing the generated Pigeon interface directly.
 *
 * Backed by the gomobile-bound github.com/gotd/td facade (go/oxtelegram) — replacing TDLib per
 * prancy-rolling-kernighan.md. The underlying OxTelegramClient is created lazily on the first
 * [configure] call and deliberately NOT kept alive between playback sessions:
 * [onTelegramPlaybackEnded] closes it as soon as a Telegram-sourced playback session ends
 * (matches the idle-close discipline already proven this migration's predecessor session, kept
 * here even though gotd/td has no TDLib-style forced-backlog-sync problem to work around); the
 * on-disk session persists so the next play just reconnects rather than needing a fresh login.
 *
 * WebApp/Mini-App auth ([fetchWebAppInitData], the separate OX-account login-via-Telegram flow)
 * is not yet ported to gotd/td — see plan Phase 4 (hard requirement, not yet investigated).
 */
object TdlibBridgeObject : OxTdlibBridgeApi {

    /** TEMPORARILY true for the joint device-testing pass (2026-08-10) validating the JNI
     *  round-trip on a real device for the first time — see OxTelegramStreamBridge's doc. Flip
     *  back to false if this test session finds a real bug, or leave true once confirmed working
     *  and consider removing the HTTP bridge fallback entirely (as already done on Windows). */
    private const val OX_TELEGRAM_STREAM_CB_ENABLED = true

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context
    private var events: OxTdlibBridgeEvents? = null

    private var client: OxTelegramClient? = null
    private var authController: OxTelegramAuthController? = null
    private var sessionStorage: OxTelegramSessionStorage? = null
    private var fileFetcher: OxTelegramFileFetcher? = null

    /** Synthetic per-session token (gotd/td's PlaybackSession has no TDLib-style int fileId of
     *  its own) minted into the tdlib-file://{id} / http://127.0.0.1:{port}/{id} URI so
     *  stopPlaybackSession can round-trip it back to [closeAfterPlayback]. Only one playback
     *  session is ever live at a time (this module's whole scope), so uniqueness across restarts
     *  is all that's needed, not a real lookup key. */
    private val playbackIdCounter = AtomicInteger(0)

    /** id of the in-flight/just-finished Telegram-sourced playback session, if any — lets
     *  [onTelegramPlaybackEnded] no-op for non-Telegram playback and know what to cancel. */
    @Volatile
    private var currentPlaybackFileId: Int? = null

    /** mpv/mdk path (see TdlibHttpBridgeServer doc) — created once, outlives individual
     *  OxTelegramClient instances; always reads whichever [fileFetcher] is live at request time. */
    private val httpBridgeServer = TdlibHttpBridgeServer(fileFetcher = { fileFetcher })

    @Volatile
    private var lastAuthState: OxTdlibAuthState =
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.UNINITIALIZED)

    /** Call once from MainActivity.configureFlutterEngine, alongside OxTdlibBridgeApi.setUp. */
    fun attach(context: Context, binaryMessenger: BinaryMessenger) {
        appContext = context.applicationContext
        events = OxTdlibBridgeEvents(binaryMessenger)
    }

    override fun configure(apiId: Long, apiHash: String, callback: (Result<Unit>) -> Unit) {
        val existing = client
        val existingAuth = authController
        if (existing != null && existingAuth != null) {
            // Hot restart / re-prepare: client already live — push current auth to Dart immediately.
            onAuthStateChanged(existingAuth.state.value)
            callback(Result.success(Unit))
            return
        }
        if (existing != null) {
            existing.close()
            clearNativeSession()
        }

        val storage = OxTelegramSessionStorage(appContext)
        val oxClient = OxTelegramClient(apiId, apiHash, storage)
        val controller = OxTelegramAuthController(oxClient)
        client = oxClient
        authController = controller
        sessionStorage = storage

        scope.launch {
            controller.state.collect { state ->
                if (authController !== controller) return@collect
                onAuthStateChanged(state)
            }
        }
        scope.launch {
            runCatching { oxClient.configure(controller.sink) }
                .onFailure { err ->
                    Log.e("OXPLAY_TDLIB", "oxtelegram configure failed", err)
                    if (authController === controller) {
                        onAuthStateChanged(TdlibAuthState.Failed(err))
                    }
                }
        }
        callback(Result.success(Unit))
    }

    override fun currentAuthState(): OxTdlibAuthState = lastAuthState

    /** Current OxTelegramFileFetcher, if a playback session is active — looked up fresh per
     *  playback open (not cached at composable-remember time) since a new startPlaybackSession
     *  swaps it out. */
    fun currentFileFetcher(): OxTelegramFileFetcher? = fileFetcher

    override fun submitPhoneNumber(phoneNumber: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitPhoneNumber(phoneNumber) }
    }

    override fun submitCode(code: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitCode(code) }
    }

    override fun submitTwoFactorPassword(password: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitTwoFactorPassword(password) }
    }

    override fun requestQrLogin(callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().requestQrLogin() }
    }

    override fun logOut(callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) {
            val controller = authController
            if (controller != null) {
                runCatching { controller.logOut() }
            }
            client?.close()
            sessionStorage?.clear()
            clearNativeSession()
        }
    }

    /** Drop the live client so the next [configure] starts a fresh auth machine. */
    private fun clearNativeSession() {
        client = null
        authController = null
        sessionStorage = null
        fileFetcher = null
        lastAuthState = OxTdlibAuthState(kind = OxTdlibAuthStateKind.UNINITIALIZED)
        runOnMain {
            events?.onAuthStateChanged(lastAuthState) { }
        }
    }

    override fun startPlaybackSession(
        source: OxTdlibPlaybackSource,
        callback: (Result<String>) -> Unit,
    ) {
        Log.i("OXPLAY_TDLIB", "startPlaybackSession received channel=${source.channelUsername} messageId=${source.messageId}, dispatching")
        scope.launch {
            Log.i("OXPLAY_TDLIB", "startPlaybackSession coroutine started")
            runCatching {
                val oxClient = client ?: notConfigured()
                val session = oxClient.startPlaybackSession(
                    source.channelUsername,
                    source.messageId,
                    appContext.cacheDir.absolutePath,
                )
                val fileId = playbackIdCounter.incrementAndGet()
                fileFetcher = OxTelegramFileFetcher(session)
                currentPlaybackFileId = fileId
                Log.i("OXPLAY_TDLIB", "startPlaybackSession resolved fileId=$fileId size=${session.size()} mime=${session.mimeType()}")
                when {
                    !source.preferHttpBridge -> "tdlib-file://${fileId}"
                    OX_TELEGRAM_STREAM_CB_ENABLED -> {
                        // stream_cb path (go/oxtelegram/cshared_android) — untested on-device as of
                        // this writing; see OxTelegramStreamBridge's doc. Flip the flag above once
                        // validated in the joint device-testing pass; until then this branch is dead
                        // and playback keeps using the proven HTTP bridge below. Reuses fileId (not
                        // a separate counter) so closeAfterPlayback's cleanup covers this too.
                        OxTelegramStreamBridge.registerSession(fileId, session)
                        "gotdstream://${fileId}"
                    }
                    else -> httpBridgeServer.urlFor(fileId)
                }
            }.fold(
                onSuccess = { uri -> replyOnMain(callback, Result.success(uri)) },
                onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
            )
        }
    }

    /**
     * Called from mpv/mdk's wrapper (media_control_wrapper.dart) when a Telegram-sourced item
     * finishes — mpv/mdk have no Activity-scoped teardown hook the way ExoPlayer does (see
     * [onTelegramPlaybackEnded]), so that path must call this explicitly via Pigeon. sessionUri is
     * either tdlib-file://{fileId} or http://127.0.0.1:{port}/{fileId} (TdlibHttpBridgeServer) —
     * fileId is the last path segment either way.
     */
    override fun stopPlaybackSession(sessionUri: String, callback: (Result<Unit>) -> Unit) {
        val fileId = sessionUri.substringAfterLast('/').toIntOrNull()
        if (fileId != null) closeAfterPlayback(fileId)
        callback(Result.success(Unit))
    }

    /**
     * Called from the native player's teardown (VideoPlayerImplementation.clearSession) once a
     * Telegram-sourced playback session actually ends — not via the Pigeon stopPlaybackSession
     * path, since ExoPlayer runs in its own Activity with a reliable native-side onDispose hook
     * that already fires exactly when ExoPlayer is released (including activity-finish/app-kill
     * paths), so no Dart round-trip is needed for that backend.
     *
     * No-op if the just-ended playback wasn't Telegram-sourced (currentPlaybackFileId unset).
     */
    fun onTelegramPlaybackEnded() {
        val fileId = currentPlaybackFileId ?: return
        closeAfterPlayback(fileId)
    }

    /**
     * End the active download/session but keep the TDLib client alive (READY).
     * Closing the whole client after every play forced the next play to reconfigure from
     * UNINITIALIZED (~0.5–2s+), which dominated first-frame latency. Session auth stays on disk
     * either way; keeping the live client just avoids that reconnect tax between plays.
     */
    private fun closeAfterPlayback(fileId: Int) {
        if (currentPlaybackFileId != fileId) return
        currentPlaybackFileId = null
        val fetcher = fileFetcher
        fileFetcher = null
        if (fetcher != null) {
            scope.launch { runCatching { fetcher.cancelDownload(fileId) } }
        }
        OxTelegramStreamBridge.unregisterSession(fileId)
        Log.i("OXPLAY_TDLIB", "closeAfterPlayback fileId=$fileId — client kept alive")
    }

    override fun fetchWebAppInitData(
        botUsername: String,
        webAppShortName: String?,
        hostedHttpsUrl: String?,
        callback: (Result<String>) -> Unit,
    ) {
        Log.i("OXPLAY_TDLIB", "fetchWebAppInitData botUsername=$botUsername webAppShortName=$webAppShortName hostedHttpsUrl=$hostedHttpsUrl")
        scope.launch {
            runCatching {
                val oxClient = client ?: notConfigured()
                oxClient.fetchWebAppInitData(botUsername, webAppShortName ?: "", hostedHttpsUrl ?: "")
            }.fold(
                onSuccess = { initData ->
                    Log.i("OXPLAY_TDLIB", "fetchWebAppInitData OK len=${initData.length} value=$initData")
                    replyOnMain(callback, Result.success(initData))
                },
                onFailure = { error ->
                    Log.e("OXPLAY_TDLIB", "fetchWebAppInitData FAILED", error)
                    replyOnMain(callback, Result.failure(error))
                },
            )
        }
    }

    private fun onAuthStateChanged(state: TdlibAuthState) {
        val mapped = state.toPigeon()
        lastAuthState = mapped
        Log.i("ox-tdlib-auth", "native auth → ${mapped.kind}")
        // Pigeon BasicMessageChannel.send → FlutterJNI requires @UiThread / main.
        runOnMain { events?.onAuthStateChanged(mapped) { } }
    }

    private fun runOrFail(callback: (Result<Unit>) -> Unit, block: suspend () -> Unit) {
        scope.launch {
            runCatching { block() }
                .fold(
                    onSuccess = { replyOnMain(callback, Result.success(Unit)) },
                    onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
                )
        }
    }

    private fun <T> replyOnMain(callback: (Result<T>) -> Unit, result: Result<T>) {
        runOnMain { callback(result) }
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private fun requireAuthController(): OxTelegramAuthController =
        authController ?: notConfigured()

    private fun notConfigured(): Nothing =
        throw IllegalStateException("OxTdlibBridgeApi.configure() must be called before this method")
}

private fun TdlibAuthState.toPigeon(): OxTdlibAuthState = when (this) {
    is TdlibAuthState.Uninitialized ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.UNINITIALIZED)
    is TdlibAuthState.WaitingForPhoneNumber ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.WAITING_FOR_PHONE_NUMBER)
    is TdlibAuthState.WaitingForCode ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.WAITING_FOR_CODE)
    is TdlibAuthState.WaitingForPassword ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.WAITING_FOR_PASSWORD, passwordHint = hint)
    is TdlibAuthState.WaitingForQrConfirmation ->
        OxTdlibAuthState(
            kind = OxTdlibAuthStateKind.WAITING_FOR_QR_CONFIRMATION,
            qrLoginUrl = loginUrl,
            errorMessage = notice.ifEmpty { null },
        )
    is TdlibAuthState.Ready ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.READY)
    is TdlibAuthState.LoggingOut ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.LOGGING_OUT)
    is TdlibAuthState.Closed ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.CLOSED)
    is TdlibAuthState.Failed ->
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.FAILED, errorMessage = error.message)
}
