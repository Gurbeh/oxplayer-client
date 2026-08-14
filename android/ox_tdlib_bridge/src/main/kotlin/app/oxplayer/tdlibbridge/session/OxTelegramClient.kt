package app.oxplayer.tdlibbridge.session

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import mobile.AuthEventSink
import mobile.Client
import mobile.PlaybackSession
import mobile.SessionStorage

/**
 * Coroutine-friendly wrapper around the gomobile-bound mobile.Client (github.com/gotd/td facade,
 * go/oxtelegram) — the replacement for TdlibClient. Every mobile.Client method is already a
 * plain blocking JNI call (gotd/td's auth API is call/response, not TDLib's async
 * request/response protocol needing a CompletableDeferred bridge), so this just moves each call
 * onto Dispatchers.IO so it doesn't block the calling coroutine's thread.
 */
class OxTelegramClient(
    apiId: Long,
    apiHash: String,
    storage: SessionStorage,
) {
    val native: Client = Client(apiId, apiHash, storage)

    suspend fun configure(sink: AuthEventSink) = withContext(Dispatchers.IO) { native.configure(sink) }

    suspend fun submitPhoneNumber(phone: String) = withContext(Dispatchers.IO) { native.submitPhoneNumber(phone) }

    suspend fun submitBotToken(token: String) = withContext(Dispatchers.IO) { native.submitBotToken(token) }

    suspend fun submitCode(code: String) = withContext(Dispatchers.IO) { native.submitCode(code) }

    suspend fun submitTwoFactorPassword(password: String) =
        withContext(Dispatchers.IO) { native.submitTwoFactorPassword(password) }

    suspend fun requestQrLogin() = withContext(Dispatchers.IO) { native.requestQrLogin() }

    suspend fun logOut() = withContext(Dispatchers.IO) { native.logOut() }

    suspend fun startPlaybackSession(
        providerBotId: Long,
        messageId: Long,
        cacheDir: String,
        locator: String,
    ): PlaybackSession =
        withContext(Dispatchers.IO) {
            native.startPlaybackSession(providerBotId, messageId, cacheDir, locator)
        }

    /**
     * Resolves the delivery and records where it landed, without opening a download — the warm-up
     * path. Still a real MTProto call, so it belongs on Dispatchers.IO.
     */
    suspend fun warmDelivery(providerBotId: Long, messageId: Long, locator: String) =
        withContext(Dispatchers.IO) {
            native.warmDelivery(providerBotId, messageId, locator)
        }

    /**
     * Starts, mutes and archives every delivery sender. [botsJson] is
     * `[{"id":123,"username":"SomeBot"}]` — gomobile cannot bind a slice of structs, so the list
     * crosses the JNI boundary as JSON.
     */
    suspend fun ensureProviderBotsReady(botsJson: String) =
        withContext(Dispatchers.IO) { native.ensureProviderBotsReady(botsJson) }

    /**
     * Registers interest in [locator] before the delivery is requested. Touches an in-memory map on
     * the Go side — no MTProto round-trip, so it stays off Dispatchers.IO.
     */
    fun armDeliveryWaiter(locator: String) = native.armDeliveryWaiter(locator)

    /**
     * The DM message id this session read for [locator], or 0. Reads an in-memory map on the Go
     * side — no MTProto round-trip, so it stays off Dispatchers.IO and can answer a synchronous
     * Pigeon call.
     */
    fun deliveryMessageIDForLocator(locator: String): Long = native.deliveryMessageIDForLocator(locator)

    /** The delivery bot whose DM held [locator], or 0. Same in-memory read as above. */
    fun deliveryProviderBotIDForLocator(locator: String): Long = native.deliveryProviderBotIDForLocator(locator)

    suspend fun fetchWebAppInitData(
        botUsername: String,
        webAppShortName: String,
        hostedHttpsUrl: String,
        platform: String = "android",
    ): String = withContext(Dispatchers.IO) {
        native.fetchWebAppInitData(botUsername, webAppShortName, hostedHttpsUrl, platform)
    }

    /** Fire-and-forget from the caller's perspective — mirrors TdlibClient.close(). */
    fun close() {
        runCatching { native.close() }
    }
}
