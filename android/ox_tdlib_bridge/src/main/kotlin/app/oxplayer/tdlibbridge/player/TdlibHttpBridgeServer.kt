package app.oxplayer.tdlibbridge.player

import android.util.Log
import app.oxplayer.tdlibbridge.media.OxFileInfo
import app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

private const val TAG = "OXPLAY_TDLIB"
private const val READ_CHUNK_BYTES = 64 * 1024
/** Prefetch enough for mkv after seek so the first Range body can start immediately. */
private const val READ_AHEAD_BYTES = 2L * 1024 * 1024
private const val CRLF = "\r\n"

/**
 * Minimal loopback-only HTTP/1.1 server exposing TDLib-backed files as plain http:// byte-range
 * streams — the same TdlibFileFetcher/DownloadFile machinery TelegramFileDataSource uses for
 * ExoPlayer, just reached over a socket instead of media3's DataSource interface.
 *
 * Exists for mpv/mdk (via libmpv/media_kit): unlike ExoPlayer, there's no equivalent to a custom
 * DataSource short of native stream_cb, and bridging that across the Dart-FFI/libmpv boundary to
 * our JNI-based TDLib client (which lives on the JVM side) is a much larger undertaking than
 * handing mpv a URL it already knows how to play — mpv/ffmpeg's http protocol already understands
 * Range requests, so no custom client-side protocol code is needed at all.
 *
 * Binds 127.0.0.1 only (never a wildcard/public address) — never reachable off-device. One
 * response per connection (`Connection: close`): mpv/ffmpeg simply opens a new connection for the
 * next range on a seek, which is negligible overhead on loopback and avoids implementing
 * HTTP/1.1 keep-alive/pipelining for a server with exactly one real client.
 */
class TdlibHttpBridgeServer(private val fileFetcher: (Int) -> OxTelegramFileFetcher?) {
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var port: Int = -1
    private val running = AtomicBoolean(false)
    private val scope = CoroutineScope(Dispatchers.IO)
    /** Concurrent HTTP bodies (MKV cue + cluster). Download stays running until playback session ends. */
    private val activeStreams = AtomicInteger(0)

    /** Starts the accept loop if not already running; returns the bound port. Idempotent. */
    @Synchronized
    fun ensureStarted(): Int {
        serverSocket?.let { return port }
        val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        serverSocket = socket
        port = socket.localPort
        running.set(true)
        scope.launch { acceptLoop(socket) }
        Log.i(TAG, "TdlibHttpBridgeServer started on 127.0.0.1:$port")
        return port
    }

    fun urlFor(fileId: Int): String = "http://127.0.0.1:${ensureStarted()}/$fileId"

    private fun acceptLoop(socket: ServerSocket) {
        while (running.get()) {
            val client = try {
                socket.accept()
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "TdlibHttpBridgeServer accept failed: ${e.message}")
                break
            }
            scope.launch {
                runCatching { handleClient(client) }
                    .onFailure { Log.d(TAG, "TdlibHttpBridgeServer client ended: ${it.message}") }
            }
        }
    }

    private suspend fun handleClient(client: Socket) {
        client.use { sock ->
            sock.soTimeout = 30_000
            val input = sock.getInputStream().bufferedReader(Charsets.ISO_8859_1)
            val requestLine = input.readLine() ?: return
            val requestParts = requestLine.split(" ")
            if (requestParts.size < 2) return
            val method = requestParts[0]
            val path = requestParts[1]

            var rangeHeader: String? = null
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
                if (line.startsWith("Range:", ignoreCase = true)) {
                    rangeHeader = line.substringAfter(":").trim()
                }
            }

            val fileId = path.removePrefix("/").substringBefore('?').toIntOrNull()
            // Resolved by the id in the request path, not by "whichever session is current": a url
            // whose session already ended must 404 rather than quietly stream the bytes of a
            // different play that happens to be active now.
            val fetcher = fileId?.let { fileFetcher(it) }
            val output = sock.getOutputStream()
            Log.i(TAG, "HTTP request method=$method path=$path range=$rangeHeader fileId=$fileId")
            if (fileId == null || fetcher == null) {
                writeStatusOnly(output, 404, "Not Found")
                return
            }
            if (method != "GET" && method != "HEAD") {
                writeStatusOnly(output, 405, "Method Not Allowed")
                return
            }
            serveFile(output, fetcher, fileId, rangeHeader, headOnly = method == "HEAD")
        }
    }

    private fun parseRangeStart(rangeHeader: String?): Long {
        val spec = rangeHeader?.removePrefix("bytes=") ?: return 0L
        return spec.substringBefore('-').toLongOrNull() ?: 0L
    }

    private fun parseRangeEnd(rangeHeader: String?, lastByte: Long): Long? {
        if (rangeHeader == null) return null
        val spec = rangeHeader.removePrefix("bytes=")
        val endPart = spec.substringAfter('-', missingDelimiterValue = "")
        if (endPart.isEmpty()) return null
        return endPart.toLongOrNull()?.coerceAtMost(lastByte)
    }

    private suspend fun serveFile(
        output: OutputStream,
        fetcher: OxTelegramFileFetcher,
        fileId: Int,
        rangeHeader: String?,
        headOnly: Boolean,
    ) {
        val start = parseRangeStart(rangeHeader)
        // Prefetch enough for mkv/ffmpeg after seek (same READ_AHEAD as TelegramFileDataSource).
        val probeStartedAt = System.currentTimeMillis()
        val probeWant = READ_AHEAD_BYTES
        // Must not throw past here without writing a response: this runs BEFORE any status line
        // is sent, so an escaping exception closes the socket with zero bytes written and the
        // player sees no status code at all — it just retries forever and the UI sits on an
        // endless spinner. A dead MTProto session ("waitSession: connection dead") reproduces
        // exactly that, so surface it as a real 503 instead.
        val probe = try {
            fetcher.requestDownload(fileId, offset = start, priority = 32)
            fetcher.awaitBytesAvailable(fileId, start, minBytesAvailable = probeWant)
        } catch (e: Exception) {
            Log.w(
                TAG,
                "HTTP probe FAILED fileId=$fileId start=$start " +
                    "tookMs=${System.currentTimeMillis() - probeStartedAt} — ${e.message}",
            )
            writeStatusOnly(output, 503, "Service Unavailable")
            return
        }
        Log.i(
            TAG,
            "HTTP probe fileId=$fileId start=$start want=$probeWant " +
                "tookMs=${System.currentTimeMillis() - probeStartedAt} size=${probe.size} windowEnd=${probe.windowEnd}",
        )
        val size = probe.size
        if (size <= 0L || start >= size) {
            writeStatusOnly(output, 416, "Range Not Satisfiable")
            return
        }
        val lastByte = size - 1
        val explicitEnd = parseRangeEnd(rangeHeader, lastByte)
        // Open-ended `Range: bytes=N-` (and no Range) must run to EOF. ffmpeg's http protocol
        // treats a short 206 as "Stream ends prematurely at X, should be <filesize>" and
        // reconnects every chunk — 2MB caps caused I/O-error reconnect storms on session play.
        val end = explicitEnd ?: lastByte
        val contentLength = end - start + 1
        val isPartial = rangeHeader != null || end < lastByte

        val writer = StringBuilder()
        if (isPartial) {
            writer.append("HTTP/1.1 206 Partial Content").append(CRLF)
            writer.append("Content-Range: bytes $start-$end/$size").append(CRLF)
        } else {
            writer.append("HTTP/1.1 200 OK").append(CRLF)
        }
        writer.append("Accept-Ranges: bytes").append(CRLF)
        writer.append("Content-Type: application/octet-stream").append(CRLF)
        writer.append("Content-Length: $contentLength").append(CRLF)
        writer.append("Connection: close").append(CRLF)
        writer.append(CRLF)
        output.write(writer.toString().toByteArray(Charsets.ISO_8859_1))
        if (headOnly || contentLength <= 0L) {
            output.flush()
            return
        }

        activeStreams.incrementAndGet()
        try {
            streamRange(
                output,
                fetcher,
                fileId,
                probe.localPath,
                start,
                end,
                probe.windowEnd,
                probe.isDownloadingCompleted,
            )
        } finally {
            if (activeStreams.decrementAndGet() <= 0) {
                // Leave in-flight bytes; closeAfterPlayback cancels. Cancelling here raced the
                // next Range (ffmpeg reconnect / cue→cluster) and reset the gotd window.
                Log.d(TAG, "last HTTP stream closed fileId=$fileId (download left running)")
            }
        }
    }

    /** Mirrors TelegramFileDataSource's known-available-window cache: only round-trips into the
     *  facade when a chunk is about to read past what was last confirmed available, instead of
     *  on every chunk (see that class's doc for the GetFile-flood bug this avoids). */
    private suspend fun streamRange(
        output: OutputStream,
        fetcher: OxTelegramFileFetcher,
        fileId: Int,
        localPath: String,
        start: Long,
        end: Long,
        initialKnownAvailableUpTo: Long,
        initialFullyDownloaded: Boolean,
    ) {
        var knownAvailableUpTo = initialKnownAvailableUpTo
        var fullyDownloaded = initialFullyDownloaded
        val streamStartedAt = System.currentTimeMillis()
        var totalWritten = 0L
        val raf = RandomAccessFile(localPath, "r")
        raf.use {
            raf.seek(start)
            var position = start
            val buffer = ByteArray(READ_CHUNK_BYTES)
            while (position <= end) {
                val wantLength = minOf(READ_CHUNK_BYTES.toLong(), end - position + 1)
                if (!fullyDownloaded && position + wantLength > knownAvailableUpTo) {
                    val waitStartedAt = System.currentTimeMillis()
                    val file: OxFileInfo = fetcher.awaitBytesAvailable(fileId, position, wantLength)
                    val waitMs = System.currentTimeMillis() - waitStartedAt
                    if (waitMs > 500) {
                        Log.w(
                            TAG,
                            "HTTP stream fileId=$fileId slow awaitBytesAvailable position=$position " +
                                "wantLength=$wantLength tookMs=$waitMs windowEnd=${file.windowEnd} " +
                                "complete=${file.isDownloadingCompleted}",
                        )
                    }
                    knownAvailableUpTo = file.windowEnd
                    fullyDownloaded = file.isDownloadingCompleted
                }
                val readLength = wantLength.toInt()
                val bytesRead = raf.read(buffer, 0, readLength)
                if (bytesRead <= 0) break
                output.write(buffer, 0, bytesRead)
                position += bytesRead
                totalWritten += bytesRead
            }
            output.flush()
        }
        Log.i(
            TAG,
            "HTTP stream fileId=$fileId range=$start-$end totalWritten=$totalWritten " +
                "tookMs=${System.currentTimeMillis() - streamStartedAt} active=${activeStreams.get()}",
        )
    }

    private fun writeStatusOnly(output: OutputStream, code: Int, reason: String) {
        val response = "HTTP/1.1 $code $reason$CRLF" +
            "Connection: close$CRLF" +
            "Content-Length: 0$CRLF$CRLF"
        runCatching { output.write(response.toByteArray(Charsets.ISO_8859_1)); output.flush() }
    }
}
