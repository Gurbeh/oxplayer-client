package app.oxplayer.objects

import android.util.Log
import OxTdlibAuthState
import OxTdlibAuthStateKind
import OxTdlibBridgeApi
import OxTdlibBridgeEvents
import OxTdlibConnectionHealth
import OxTdlibDeliveryRef
import OxTdlibPlaybackSource
import OxTdlibProviderBot
import android.content.Context
import android.content.Intent
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
import mobile.ConnectionSink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Singleton bridging Flutter (OxTdlibBridgeApi, Pigeon-generated) to ox_tdlib_bridge's Kotlin
 * classes, mirroring this app's PlayerSettingsObject/VideoPlayerObject convention of an object
 * implementing the generated Pigeon interface directly.
 *
 * Backed by the gomobile-bound github.com/gotd/td facade (go/oxtelegram) — replacing TDLib per
 * prancy-rolling-kernighan.md.
 *
 * Two lifetimes live here and must not be confused — conflating them is what produced the
 * "No active TDLib session for playback" reports from TV devices whose login was perfectly healthy:
 *
 *  - The **OxTelegramClient** (MTProto socket + auth) is created lazily on the first [configure]
 *    call and then kept alive for the whole process. Nothing closes it except [logOut]. It is
 *    cheap to hold — a socket, session keys, and three self-pruning maps in go/oxtelegram's
 *    Client — whereas rebuilding it costs a ~0.5-2s reconnect that lands squarely on first-frame
 *    latency. An earlier revision closed it after every play as a precaution against memory use
 *    that was never actually measured; that is deliberately not done any more.
 *  - A **playback session** ([OxTelegramFileFetcher] over a gotd/td PlaybackSession) lives for
 *    exactly one play. It is registered in [fetchers] under the synthetic fileId minted into its
 *    uri, and released by [onTelegramPlaybackEnded] — which must be told WHICH fileId ended, since
 *    the next play's session may already have been started by the time the previous player's
 *    teardown runs. Its bytes land in an on-disk .part file, so holding one costs a file handle
 *    and a DC connection, not video-sized memory.
 *
 * WebApp/Mini-App auth ([fetchWebAppInitData], the separate OX-account login-via-Telegram flow)
 * is not yet ported to gotd/td — see plan Phase 4 (hard requirement, not yet investigated).
 */
object TdlibBridgeObject : OxTdlibBridgeApi {

    /** Flipped back to false (2026-08-13): on-device testing reproduced a full app freeze/ANR
     *  (mpv's demuxer thread stuck inside ox_stream_open_fn's JNI round-trip, ~44s of total
     *  silence — no Flutter log output at all, not even unrelated screens — ending in Android
     *  killing the process) on the second/third real playback in a session, right after a large
     *  dashboard-prefetch burst. Root cause not yet isolated (native crash trace rolls out of the
     *  logcat ring buffer before it can be captured), but it reliably reproduced with this flag on
     *  and did not reproduce on the proven HTTP bridge path — see jni_bridge.go's doc for the
     *  round-trip this bypasses. Re-enable only after that hang is root-caused and fixed. */
    private const val OX_TELEGRAM_STREAM_CB_ENABLED = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context
    private var events: OxTdlibBridgeEvents? = null

    private var client: OxTelegramClient? = null
    private var authController: OxTelegramAuthController? = null
    private var sessionStorage: OxTelegramSessionStorage? = null

    /** Synthetic per-session token (gotd/td's PlaybackSession has no TDLib-style int fileId of
     *  its own) minted into the tdlib-file://{id} / http://127.0.0.1:{port}/{id} URI so
     *  stopPlaybackSession can round-trip it back to [closeAfterPlayback]. */
    private val playbackIdCounter = AtomicInteger(0)

    /**
     * Live playback sessions by fileId.
     *
     * Normally holds at most one. It is a map rather than a single field because the two events
     * that bound a session's life are not ordered: Dart resolves the NEXT play's url (minting a new
     * fileId and fetcher) before the PREVIOUS player's teardown runs. With a single field the new
     * fetcher was already installed when teardown fired, so teardown nulled the wrong one and the
     * about-to-start playback opened a url with no byte pipe behind it — the TV bug. Keyed by
     * fileId, each teardown releases exactly the session it owned, and no session is orphaned
     * un-Closed either.
     */
    private val fetchers = ConcurrentHashMap<Int, OxTelegramFileFetcher>()

    /** id of the most recently started Telegram-sourced playback session, if any. Only used to
     *  answer [currentFileFetcher] for callers that have no fileId in hand; teardown always goes
     *  through an explicit id instead. */
    @Volatile
    private var currentPlaybackFileId: Int? = null

    /** mpv/mdk path (see TdlibHttpBridgeServer doc) — created once, outlives individual
     *  OxTelegramClient instances; always reads whichever session is live at request time. */
    private val httpBridgeServer = TdlibHttpBridgeServer(fileFetcher = { id -> fileFetcherFor(id) })

    @Volatile
    private var lastAuthState: OxTdlibAuthState =
        OxTdlibAuthState(kind = OxTdlibAuthStateKind.UNINITIALIZED)

    @Volatile
    private var lastConnectionHealth: OxTdlibConnectionHealth = OxTdlibConnectionHealth.UNINITIALIZED

    /** Forwards go/oxtelegram's health transitions to Dart. Held as a field so the same instance is
     *  reused across configure calls rather than stacking listeners on the Go side. */
    private val connectionSink = ConnectionSink { state ->
        val mapped = when (state) {
            "connecting" -> OxTdlibConnectionHealth.CONNECTING
            "ready" -> OxTdlibConnectionHealth.READY
            "degraded" -> OxTdlibConnectionHealth.DEGRADED
            else -> OxTdlibConnectionHealth.UNINITIALIZED
        }
        lastConnectionHealth = mapped
        Log.i("OXPLAY_TDLIB", "connection health -> $state")
        runOnMain { events?.onConnectionHealthChanged(mapped) { } }
    }

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
            // A live client object is NOT proof of a live connection: gotd does not resurrect a run
            // loop that exited, and the client keeps answering as if healthy afterwards. Returning
            // here unconditionally (as this did) made the Go-side rebuild unreachable from Dart, so
            // a dropped socket could only be fixed by killing the app. Kick a reconnect instead —
            // it is a no-op when the connection really is healthy.
            scope.launch { runCatching { existing.ensureConnected(existingAuth.sink) } }
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
        // Before configure, so the connecting -> ready transitions of this very run reach Dart.
        oxClient.setConnectionSink(connectionSink)

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

    override fun isNativeSessionBot(): Boolean = client?.isBotMode() ?: false

    override fun connectionHealth(): OxTdlibConnectionHealth = lastConnectionHealth

    override fun reconnect(callback: (Result<Unit>) -> Unit) {
        val oxClient = client
        val controller = authController
        if (oxClient == null || controller == null) {
            // Never configured (or logged out): there is no session to revive, and reporting this as
            // a connection failure would push the UI toward a reconnect spinner when what is
            // actually needed is configure/login.
            replyOnMain(callback, Result.failure(IllegalStateException("Telegram client not configured")))
            return
        }
        scope.launch {
            runCatching { oxClient.ensureConnected(controller.sink) }.fold(
                onSuccess = { replyOnMain(callback, Result.success(Unit)) },
                onFailure = { error ->
                    Log.w("OXPLAY_TDLIB", "reconnect failed", error)
                    replyOnMain(callback, Result.failure(error))
                },
            )
        }
    }

    /** Most recently started playback session, if one is still live — looked up fresh per playback
     *  open (not cached at composable-remember time) since a new startPlaybackSession swaps it out.
     *  Prefer [fileFetcherFor] wherever the caller already knows which fileId it is opening. */
    fun currentFileFetcher(): OxTelegramFileFetcher? = currentPlaybackFileId?.let { fetchers[it] }

    /** The session behind `tdlib-file://{fileId}` / the HTTP bridge's `/{fileId}`, or null if it
     *  already ended. Exact rather than "whatever is current", so a stale uri can never be served
     *  bytes from a different play. */
    fun fileFetcherFor(fileId: Int): OxTelegramFileFetcher? = fetchers[fileId]

    /** Whether any Telegram login is live, for telling "not logged in" apart from "this playback's
     *  session ended" when a fetcher lookup misses. */
    fun hasLiveAuth(): Boolean = lastAuthState.kind == OxTdlibAuthStateKind.READY

    override fun submitPhoneNumber(phoneNumber: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitPhoneNumber(phoneNumber) }
    }

    override fun submitCode(code: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitCode(code) }
    }

    override fun submitBotToken(token: String, callback: (Result<Unit>) -> Unit) {
        runOrFail(callback) { requireAuthController().submitBotToken(token) }
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

    /**
     * Kills and relaunches the app process — session storage on disk is untouched, this is not a
     * logout. See restartApp's doc in pigeons/tdlib_bridge.dart for why a plain in-memory
     * reconfigure cannot always recover a stuck/failed native client, and this can.
     *
     * Confirmed on-device (2026-08-17, Pixel 10 Pro / Android 16): scheduling the relaunch via
     * AlarmManager + a PendingIntent — the usual "give the OS a moment before killing the
     * process" trick — silently dropped the activity start: modern Android's background-activity-
     * launch restrictions block a PendingIntent-fired Activity once the originating process is
     * already dead, since by then there is no foreground/"recently interacted" grant left to
     * exempt it. Starting the Activity directly and *synchronously*, while this call is still
     * running inside the still-foreground button tap that triggered it, carries that exemption
     * and does not need AlarmManager's delay at all.
     */
    override fun restartApp(callback: (Result<Unit>) -> Unit) {
        callback(Result.success(Unit))
        val intent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
        if (intent == null) {
            Log.e("OXPLAY_TDLIB", "restartApp: no launch intent for ${appContext.packageName}")
            return
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        appContext.startActivity(intent)
        Log.i("OXPLAY_TDLIB", "restartApp: launched fresh activity, exiting process")
        android.os.Process.killProcess(android.os.Process.myPid())
        Runtime.getRuntime().exit(0)
    }

    /** Drop the live client so the next [configure] starts a fresh auth machine. */
    private fun clearNativeSession() {
        client = null
        authController = null
        sessionStorage = null
        // Log out / reconfigure invalidates every session at once — release them all rather than
        // dropping the references and leaking their file handles and DC connections.
        val orphaned = fetchers.values.toList()
        fetchers.clear()
        currentPlaybackFileId = null
        if (orphaned.isNotEmpty()) {
            scope.launch { orphaned.forEach { fetcher -> runCatching { fetcher.close() } } }
        }
        lastAuthState = OxTdlibAuthState(kind = OxTdlibAuthStateKind.UNINITIALIZED)
        lastConnectionHealth = OxTdlibConnectionHealth.UNINITIALIZED
        runOnMain {
            events?.onAuthStateChanged(lastAuthState) { }
            events?.onConnectionHealthChanged(lastConnectionHealth) { }
        }
    }

    override fun startPlaybackSession(
        source: OxTdlibPlaybackSource,
        callback: (Result<String>) -> Unit,
    ) {
        Log.i("OXPLAY_TDLIB", "startPlaybackSession received providerBotId=${source.providerBotId} messageId=${source.messageId} locator=${source.locator}, dispatching")
        scope.launch {
            Log.i("OXPLAY_TDLIB", "startPlaybackSession coroutine started")
            runCatching {
                val oxClient = client ?: notConfigured()
                // Revive a dead run loop before asking it for bytes. Without this the download
                // fails deep inside gotd with "waitSession: connection dead", which surfaces as an
                // unexplained playback stall rather than a recoverable connection problem. No-op on
                // a healthy connection, so it costs nothing on the common path.
                authController?.let { controller ->
                    runCatching { oxClient.ensureConnected(controller.sink) }
                        .onFailure { err ->
                            Log.w("OXPLAY_TDLIB", "startPlaybackSession: reconnect attempt failed", err)
                        }
                }
                val session = oxClient.startPlaybackSession(
                    source.providerBotId,
                    source.messageId,
                    appContext.cacheDir.absolutePath,
                    source.locator,
                )
                val fileId = playbackIdCounter.incrementAndGet()
                fetchers[fileId] = OxTelegramFileFetcher(session)
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
     * Where this session actually read [locator], or null if it has read nothing. Dart reports it
     * to the backend so the next play of the same file skips the copy entirely — see the Pigeon
     * declaration for why only the receiving session can know either number.
     */
    override fun deliveryRefForLocator(locator: String): OxTdlibDeliveryRef? {
        val oxClient = client ?: return null
        val messageId = oxClient.deliveryMessageIDForLocator(locator)
        if (messageId <= 0L) return null
        return OxTdlibDeliveryRef(
            messageId = messageId,
            providerBotId = oxClient.deliveryProviderBotIDForLocator(locator),
        )
    }

    /**
     * Registers interest in [locator] before the PlaybackInfo call that triggers the copy, so a
     * delivery landing mid-request is captured rather than raced for. Cheap and idempotent.
     */
    override fun armDeliveryWaiter(locator: String) {
        client?.armDeliveryWaiter(locator)
    }

    /**
     * Resolves [source] and remembers where it landed, without opening a download — see the Pigeon
     * declaration for why warm-up must not start a byte transfer.
     */
    override fun warmDelivery(source: OxTdlibPlaybackSource, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            runCatching {
                val oxClient = client ?: notConfigured()
                oxClient.warmDelivery(source.providerBotId, source.messageId, source.locator)
            }.fold(
                onSuccess = { replyOnMain(callback, Result.success(Unit)) },
                onFailure = { error -> replyOnMain(callback, Result.failure(error)) },
            )
        }
    }

    /**
     * Starts, mutes and archives every delivery sender so copies never reach the user's inbox.
     *
     * The list crosses into Go as JSON: gomobile cannot bind a slice of structs, and one call keeps
     * the whole set atomic from Dart's point of view.
     */
    override fun ensureProviderBotsReady(
        bots: List<OxTdlibProviderBot>,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch {
            runCatching {
                val oxClient = client ?: notConfigured()
                val json = bots.joinToString(prefix = "[", postfix = "]") { bot ->
                    """{"id":${bot.id},"username":${JSONObject.quote(bot.username)}}"""
                }
                oxClient.ensureProviderBotsReady(json)
            }.fold(
                onSuccess = { replyOnMain(callback, Result.success(Unit)) },
                onFailure = { error ->
                    // Non-fatal for the app: playback still works, delivery copies just show up in
                    // the user's inbox instead of Archive. Surface it so Dart can log and move on.
                    Log.w("OXPLAY_TDLIB", "ensureProviderBotsReady failed", error)
                    replyOnMain(callback, Result.failure(error))
                },
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
     * [fileId] is the id the ENDING playback was opened with, parsed from the uri the player still
     * holds — never [currentPlaybackFileId]. Reading the current id here instead is precisely the
     * bug this signature exists to prevent: teardown of play N runs after play N+1 has already
     * started, so "current" names the wrong session and closing it leaves the starting playback
     * with a dead byte pipe.
     *
     * No-op if the just-ended playback wasn't Telegram-sourced (null [fileId]) or its session was
     * already released.
     */
    fun onTelegramPlaybackEnded(fileId: Int?) {
        if (fileId == null) return
        closeAfterPlayback(fileId)
    }

    /**
     * Release one finished playback session, keeping the MTProto client alive (see this object's
     * doc for why that split matters).
     *
     * Closes rather than merely cancelling: [OxTelegramFileFetcher.cancelDownload] only aborts
     * in-flight chunk fetches (it is the per-seek call), so dropping the reference after it left
     * the DC connection and .part file handle open for the process's lifetime. The on-disk bytes
     * are kept on purpose — replaying the title resumes from them.
     */
    private fun closeAfterPlayback(fileId: Int) {
        val fetcher = fetchers.remove(fileId)
        if (currentPlaybackFileId == fileId) currentPlaybackFileId = null
        OxTelegramStreamBridge.unregisterSession(fileId)
        if (fetcher == null) {
            Log.i("OXPLAY_TDLIB", "closeAfterPlayback fileId=$fileId — already released, no-op")
            return
        }
        scope.launch { runCatching { fetcher.close() } }
        Log.i(
            "OXPLAY_TDLIB",
            "closeAfterPlayback fileId=$fileId — session closed, client kept alive " +
                "(remaining=${fetchers.size} current=$currentPlaybackFileId)",
        )
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
        val suffix = mapped.errorMessage?.let { " ($it)" } ?: ""
        Log.i("ox-tdlib-auth", "native auth → ${mapped.kind}$suffix")
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
