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
import app.oxplayer.tdlibbridge.auth.TdlibAuthController
import app.oxplayer.tdlibbridge.auth.TdlibAuthState
import app.oxplayer.tdlibbridge.auth.TdlibWebAppAuth
import app.oxplayer.tdlibbridge.media.TdlibChannelResolver
import app.oxplayer.tdlibbridge.media.TdlibFileFetcher
import app.oxplayer.tdlibbridge.session.TdlibClient
import app.oxplayer.tdlibbridge.session.TdlibException
import app.oxplayer.tdlibbridge.session.TdlibSessionConfig
import app.oxplayer.tdlibbridge.session.applyMinimalFootprintOptions
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Singleton bridging Flutter (OxTdlibBridgeApi, Pigeon-generated) to ox_tdlib_bridge's Kotlin
 * classes, mirroring this app's PlayerSettingsObject/VideoPlayerObject convention of an object
 * implementing the generated Pigeon interface directly.
 *
 * The underlying TdlibClient is created lazily on the first [configure] call and kept alive
 * across playback sessions once authenticated (re-auth on every play would mean an unnecessary
 * network round trip — TDLib's local session makes that unnecessary). Only the per-playback file
 * download is torn down in [stopPlaybackSession], matching the module's "no persistent chat/dialog
 * state, but a live logged-in session is expected to persist" scope (README / plan doc B.2).
 */
object TdlibBridgeObject : OxTdlibBridgeApi {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context
    private var events: OxTdlibBridgeEvents? = null

    private var client: TdlibClient? = null
    private var authController: TdlibAuthController? = null
    private var channelResolver: TdlibChannelResolver? = null
    private var fileFetcher: TdlibFileFetcher? = null
    private var webAppAuth: TdlibWebAppAuth? = null

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
            // Hot restart / re-prepare: client already live — push current auth to Dart immediately
            // (updates may have already been emitted before the new Dart listener attached).
            onAuthStateChanged(existingAuth.state.value)
            scope.launch {
                runCatching { existingAuth.syncAuthorizationState() }
                if (authController === existingAuth) {
                    onAuthStateChanged(existingAuth.state.value)
                }
            }
            callback(Result.success(Unit))
            return
        }
        // Stale client without controller — tear down and recreate.
        if (existing != null) {
            existing.close()
            clearNativeSession()
        }

        val sessionConfig = TdlibSessionConfig(appContext)
        val tdlibClient = TdlibClient.start()
        scope.launch { tdlibClient.applyMinimalFootprintOptions() }
        val controller = TdlibAuthController(
            tdlibClient = tdlibClient,
            sessionConfig = sessionConfig,
            apiId = apiId.toInt(),
            apiHash = apiHash,
            scope = scope,
        )
        client = tdlibClient
        authController = controller
        channelResolver = TdlibChannelResolver(tdlibClient)
        fileFetcher = TdlibFileFetcher(tdlibClient)
        webAppAuth = TdlibWebAppAuth(tdlibClient)

        scope.launch {
            controller.state.collect { state ->
                if (authController !== controller) return@collect
                onAuthStateChanged(state)
            }
        }
        callback(Result.success(Unit))
    }

    override fun currentAuthState(): OxTdlibAuthState = lastAuthState

    /** Current TdlibFileFetcher, if a session is configured — looked up fresh per playback open
     *  (not cached at composable-remember time) since [configure]/[logOut] can swap it out. */
    fun currentFileFetcher(): TdlibFileFetcher? = fileFetcher

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
            val config = TdlibSessionConfig(appContext)
            if (controller != null) {
                runCatching { controller.logOut() }
            }
            // Close before wipe — otherwise deleteRecursively leaves locked files and the next
            // SetTdlibParameters hits "Wrong database encryption key" with a fresh key.
            client?.close()
            // Brief pause so TDLib releases file handles on the DB directory.
            Thread.sleep(150)
            config.wipeLocalDatabase()
            config.clearDatabaseEncryptionKey()
            clearNativeSession()
        }
    }

    /**
     * Drop the live TDLib client so the next [configure] starts a fresh auth machine.
     * Required after aborting QR login — TDLib cannot return from
     * WaitOtherDeviceConfirmation to WaitPhoneNumber without logOut + new client.
     */
    private fun clearNativeSession() {
        client = null
        authController = null
        channelResolver = null
        fileFetcher = null
        webAppAuth = null
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
                val resolver = channelResolver ?: notConfigured()
                val fetcher = fileFetcher ?: notConfigured()
                val file = resolver.resolveVideoFile(source.channelUsername, source.messageId)
                Log.i("OXPLAY_TDLIB", "startPlaybackSession resolved fileId=${file.id}, requesting download")
                fetcher.requestDownload(file.id, offset = 0, priority = 32)
                "tdlib-file://${file.id}"
            }.fold(
                onSuccess = { uri -> replyOnMain(callback, Result.success(uri)) },
                onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
            )
        }
    }

    override fun stopPlaybackSession(sessionUri: String, callback: (Result<Unit>) -> Unit) {
        val fetcher = fileFetcher
        val fileId = sessionUri.removePrefix("tdlib-file://").toIntOrNull()
        if (fetcher == null || fileId == null) {
            callback(Result.success(Unit))
            return
        }
        scope.launch {
            runCatching { fetcher.cancelDownload(fileId) }
                .fold(
                    onSuccess = { replyOnMain(callback, Result.success(Unit)) },
                    onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
                )
        }
    }

    override fun fetchWebAppInitData(
        botUsername: String,
        webAppShortName: String?,
        hostedHttpsUrl: String?,
        callback: (Result<String>) -> Unit,
    ) {
        scope.launch {
            runCatching {
                val auth = webAppAuth ?: notConfigured()
                auth.fetchInitData(botUsername, webAppShortName, hostedHttpsUrl)
            }.fold(
                onSuccess = { initData -> replyOnMain(callback, Result.success(initData)) },
                onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
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
                    onFailure = { error ->
                        // Prefer short TDLib message over Exception.toString()+stack in pigeon wrapError.
                        val mapped: Throwable = when (error) {
                            is TdlibException ->
                                IllegalStateException(error.error.message ?: error.message)
                            else -> error
                        }
                        replyOnMain(callback, Result.failure(mapped))
                    },
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

    private fun requireAuthController(): TdlibAuthController =
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
