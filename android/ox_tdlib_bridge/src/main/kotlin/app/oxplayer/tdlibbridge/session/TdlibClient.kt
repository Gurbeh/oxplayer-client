package app.oxplayer.tdlibbridge.session

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi

class TdlibException(val error: TdApi.Error) : Exception(error.message)

/**
 * Coroutine-friendly wrapper around org.drinkless.tdlib.Client. One instance per login/playback
 * session — per the module's narrow scope (see README), nothing here runs a persistent
 * background "Telegram client" when no auth/playback is in progress. Callers own the lifecycle:
 * [start] to create, [close] once the session ends.
 */
class TdlibClient private constructor(
    @PublishedApi internal val client: Client,
    updatesFlow: MutableSharedFlow<TdApi.Object>,
) {
    val updates: SharedFlow<TdApi.Object> = updatesFlow.asSharedFlow()

    /**
     * Sends [function] and suspends for the response.
     *
     * Confirmed against the vendored `Client.java`/`TdApi.java` (TDLib commit
     * `022d60202e446ad1287b9fb68e687c8a0760788b`, see module README): `Client.send` takes the
     * *raw* `TdApi.Function` type (Kotlin requires a star-projection, `Function<*>`, to reference
     * it), and `ResultHandler.onResult` always receives the base `TdApi.Object` regardless of the
     * request's declared `Function<R>` type parameter — so [T] is a caller-asserted expectation
     * checked at runtime here, not something the Java API itself enforces. A `TdApi.Error`
     * response always throws [TdlibException] regardless of [T].
     */
    suspend inline fun <reified T : TdApi.Object> send(function: TdApi.Function<*>): T {
        val deferred = CompletableDeferred<TdApi.Object>()
        client.send(function) { result -> deferred.complete(result) }
        return when (val result = deferred.await()) {
            is TdApi.Error -> throw TdlibException(result)
            is T -> result
            else -> error(
                "Unexpected TDLib response ${result::class.simpleName}, expected ${T::class.simpleName}",
            )
        }
    }

    /** Requests a graceful shutdown (TdApi.Close); TDLib emits UpdateAuthorizationState(Closed) when done. */
    fun close() {
        client.send(TdApi.Close()) { }
    }

    companion object {
        fun start(): TdlibClient {
            // extraBufferCapacity must never be a hard cap: the native update callback below
            // calls tryEmit (non-suspending) directly from TDLib's own thread, and a bounded
            // SUSPEND buffer makes tryEmit silently drop the value once full instead of blocking.
            // Reproduced: on a chat-heavy account, the post-auth getDifference sync floods this
            // flow with tens of thousands of unrelated chat/channel updates within a second,
            // which filled a 64-slot buffer instantly and dropped the single
            // UpdateAuthorizationState(Ready) event in the middle of it — every collector
            // (auth state, file-download progress) then waited on a state that had already
            // arrived and been lost, hanging for the full timeout even though TDLib itself
            // reached Ready in under a second.
            val updates = MutableSharedFlow<TdApi.Object>(
                replay = 8,
                extraBufferCapacity = Int.MAX_VALUE - 8,
            )
            val client = Client.create(
                { update -> updates.tryEmit(update) },
                null,
                null,
            )
            return TdlibClient(client, updates)
        }
    }
}
