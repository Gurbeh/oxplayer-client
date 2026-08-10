package app.oxplayer.tdlibbridge.player

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import mobile.PlaybackSession
import java.util.concurrent.ConcurrentHashMap

private const val TAG = "OXPLAY_TDLIB"

/**
 * JNI-callable registry bridging the stream_cb hot-path native library
 * (liboxtelegramstream_{abi}.so, go/oxtelegram/cshared_android) to the existing gomobile-bound
 * [PlaybackSession] — this class is called FROM native code (go/oxtelegram/cshared_android/
 * jni_bridge.go), not the other way; every method here is `@JvmStatic` specifically so JNI can
 * reach them via GetStaticMethodID without needing to hold an instance reference.
 *
 * Loads liboxtelegramstream.so once, lazily, on first use — mirrors how the gomobile .aar's own
 * native library is loaded automatically by its generated bindings, except this one is a plain
 * NDK .so we build ourselves (see go/oxtelegram/cshared_android/build.ps1), so nothing else
 * triggers System.loadLibrary for it.
 *
 * Call surface, and exactly when native calls each one (this is the load-bearing design decision
 * from the stream_cb migration plan, not incidental): [registerSession] once per playback open,
 * [openSessionAsync] once right after (from native's ox_stream_open_fn), and
 * [ensureAvailableAsync] only on a real cache miss during a read — never once per mpv read_fn
 * call. Mirrors the same reactive "only round-trip when about to read past the known-available
 * window" guard already proven in [TdlibHttpBridgeServer]/OxTelegramFileFetcher for the HTTP
 * bridge path.
 *
 * [openSessionAsync]/[ensureAvailableAsync]/[cancelCurrentRead] MUST dispatch onto [scope] (a
 * plain `Dispatchers.IO` thread) rather than calling [PlaybackSession] directly on the calling
 * thread. Confirmed on-device (twice — first for ensureAvailable, then again for what became
 * openSessionAsync, which originally called PlaybackSession.size()/localPath() directly and was
 * missed on the first pass): the calling thread is one liboxtelegramstream.so's own Go runtime
 * already adopted (it's inside that runtime's cgo call stack); [PlaybackSession] is backed by a
 * *different*, independently-linked Go runtime embedded in oxtelegram.aar's .so, and nesting a
 * second Go runtime's cgo entry inside the first one's call stack on the same OS thread crashes —
 * observed as both `fatal error: unknown caller pc` and, from the second instance of this same
 * bug, `fatal error: runtime.SetFinalizer: pointer not in allocated block` (the exact corruption
 * is nondeterministic, but the trigger — a nested foreign Go runtime call — is the same). Running
 * on a fresh coroutine thread avoids the nesting: that thread only ever touches the gomobile
 * runtime, never liboxtelegramstream.so's. Every PlaybackSession call reachable from native must
 * go through this pattern — there is no safe direct call from native into PlaybackSession, ever.
 */
object OxTelegramStreamBridge {
    init {
        try {
            System.loadLibrary("oxtelegramstream")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "OxTelegramStreamBridge: failed to load liboxtelegramstream.so", e)
        }
    }

    private val sessions = ConcurrentHashMap<Int, PlaybackSession>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Registers [session] under the caller-supplied [id] — callers must pass the *same* id used
     *  to build the "gotdstream://{id}" uri handed to mpv (TdlibBridgeObject's own
     *  playbackIdCounter value, not a separate counter here), so [unregisterSession] can be
     *  reached from closeAfterPlayback's existing fileId-based cleanup without a second id space
     *  to keep in sync. Mirrors TdlibHttpBridgeServer.Register(fileId, source)'s exact shape. */
    fun registerSession(id: Int, session: PlaybackSession) {
        sessions[id] = session
        Log.i(TAG, "OxTelegramStreamBridge.registerSession id=$id size=${runCatching { session.size() }.getOrNull()}")
    }

    fun unregisterSession(id: Int) {
        sessions.remove(id)
    }

    /** Called once from native's ox_stream_open_fn (see class doc for why this must dispatch onto
     *  [scope] rather than calling [PlaybackSession] on the calling thread). Reports
     *  [PlaybackSession.localPath] + [PlaybackSession.size] back via
     *  [nativeOnOpenSessionComplete]. */
    @JvmStatic
    fun openSessionAsync(id: Int, requestId: Long) {
        val session = sessions[id]
        if (session == null) {
            nativeOnOpenSessionComplete(requestId, false, "", -1L)
            return
        }
        scope.launch {
            try {
                val path = session.localPath()
                val size = session.size()
                nativeOnOpenSessionComplete(requestId, true, path, size)
            } catch (e: Exception) {
                Log.w(TAG, "OxTelegramStreamBridge.openSessionAsync failed id=$id: ${e.message}")
                nativeOnOpenSessionComplete(requestId, false, "", -1L)
            }
        }
    }

    /** Called from native only on a real cache miss (see class doc) — fires
     *  [PlaybackSession.ensureAvailable] on [scope], NOT on the calling thread (see class doc for
     *  why), then reports completion back to native via [nativeOnEnsureAvailableComplete].
     *  [requestId] is opaque to Kotlin — native mints it (a pointer to its own wait state) and
     *  expects it echoed back unchanged. */
    @JvmStatic
    fun ensureAvailableAsync(id: Int, requestId: Long, offset: Long, length: Long) {
        val session = sessions[id]
        if (session == null) {
            nativeOnEnsureAvailableComplete(requestId, false)
            return
        }
        scope.launch {
            val success = try {
                session.ensureAvailable(offset, length)
                true
            } catch (e: Exception) {
                Log.w(TAG, "OxTelegramStreamBridge.ensureAvailableAsync failed id=$id offset=$offset length=$length: ${e.message}")
                false
            }
            nativeOnEnsureAvailableComplete(requestId, success)
        }
    }

    /** Fire-and-forget — see class doc for why this must not call [PlaybackSession] on the
     *  calling (native-owned) thread. No completion signal needed: mpv's cancel_fn contract
     *  doesn't wait for cancellation to finish, only for it to have been requested. */
    @JvmStatic
    fun cancelCurrentRead(id: Int) {
        val session = sessions[id] ?: return
        scope.launch { runCatching { session.cancelCurrentRead() } }
    }

    /** Implemented natively (go/oxtelegram/cshared_android/jni_bridge.go, registered via
     *  RegisterNatives in JNI_OnLoad) — signals the native condition variable [requestId] points
     *  to. Always called from a [scope] coroutine thread, after PlaybackSession.ensureAvailable
     *  has fully returned on that same thread — never nested with it, see class doc. */
    @JvmStatic
    private external fun nativeOnEnsureAvailableComplete(requestId: Long, success: Boolean)

    /** Implemented natively — same pattern as [nativeOnEnsureAvailableComplete], for
     *  [openSessionAsync]'s result. */
    @JvmStatic
    private external fun nativeOnOpenSessionComplete(requestId: Long, success: Boolean, localPath: String, size: Long)
}
