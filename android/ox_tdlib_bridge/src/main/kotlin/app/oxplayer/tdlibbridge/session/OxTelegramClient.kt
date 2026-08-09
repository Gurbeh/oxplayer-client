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

    suspend fun submitCode(code: String) = withContext(Dispatchers.IO) { native.submitCode(code) }

    suspend fun submitTwoFactorPassword(password: String) =
        withContext(Dispatchers.IO) { native.submitTwoFactorPassword(password) }

    suspend fun requestQrLogin() = withContext(Dispatchers.IO) { native.requestQrLogin() }

    suspend fun logOut() = withContext(Dispatchers.IO) { native.logOut() }

    suspend fun startPlaybackSession(channelUsername: String, messageId: Long, cacheDir: String): PlaybackSession =
        withContext(Dispatchers.IO) { native.startPlaybackSession(channelUsername, messageId, cacheDir) }

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
