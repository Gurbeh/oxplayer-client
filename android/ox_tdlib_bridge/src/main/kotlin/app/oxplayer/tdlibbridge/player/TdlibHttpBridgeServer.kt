package app.oxplayer.tdlibbridge.player

import android.util.Log
import app.oxplayer.tdlibbridge.media.TdlibFileFetcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.drinkless.tdlib.TdApi
import java.io.OutputStream
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "OXPLAY_TDLIB"
private const val READ_CHUNK_BYTES = 64 * 1024
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
class TdlibHttpBridgeServer(private val fileFetcher: () -> TdlibFileFetcher?) {
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var port: Int = -1
    private val running = AtomicBoolean(false)
    private val scope = CoroutineScope(Dispatchers.IO)

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
            val fetcher = fileFetcher()
            val output = sock.getOutputStream()
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

    private fun parseRangeEnd(rangeHeader: String?, lastByte: Long): Long {
        val spec = rangeHeader?.removePrefix("bytes=") ?: return lastByte
        val endPart = spec.substringAfter('-', "")
        return endPart.toLongOrNull()?.coerceAtMost(lastByte) ?: lastByte
    }

    private suspend fun serveFile(
        output: OutputStream,
        fetcher: TdlibFileFetcher,
        fileId: Int,
        rangeHeader: String?,
        headOnly: Boolean,
    ) {
        val start = parseRangeStart(rangeHeader)
        // Learn total size + confirm the requested start is actually reachable before committing
        // to response headers — same "probe with a tiny want, then stream" shape as
        // TelegramFileDataSource.open().
        fetcher.requestDownload(fileId, offset = start, priority = 32)
        val probe = fetcher.awaitBytesAvailable(fileId, start, minBytesAvailable = 1L)
        val size = probe.size
        if (size <= 0L || start >= size) {
            writeStatusOnly(output, 416, "Range Not Satisfiable")
            return
        }
        val end = parseRangeEnd(rangeHeader, size - 1)
        val contentLength = end - start + 1

        val writer = StringBuilder()
        if (rangeHeader != null) {
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

        streamRange(output, fetcher, fileId, probe.local.path, start, end)
    }

    /** Mirrors TelegramFileDataSource's known-available-window cache: only round-trips into
     *  TDLib when a chunk is about to read past what was last confirmed available, instead of on
     *  every chunk (see that class's doc for the GetFile-flood bug this avoids). */
    private suspend fun streamRange(
        output: OutputStream,
        fetcher: TdlibFileFetcher,
        fileId: Int,
        localPath: String,
        start: Long,
        end: Long,
    ) {
        var knownAvailableUpTo = 0L
        var fullyDownloaded = false
        val raf = RandomAccessFile(localPath, "r")
        raf.use {
            raf.seek(start)
            var position = start
            val buffer = ByteArray(READ_CHUNK_BYTES)
            while (position <= end) {
                val wantLength = minOf(READ_CHUNK_BYTES.toLong(), end - position + 1)
                if (!fullyDownloaded && position + wantLength > knownAvailableUpTo) {
                    val file: TdApi.File = fetcher.awaitBytesAvailable(fileId, position, wantLength)
                    knownAvailableUpTo = file.local.downloadOffset + file.local.downloadedPrefixSize
                    fullyDownloaded = file.local.isDownloadingCompleted
                }
                val readLength = wantLength.toInt()
                val bytesRead = raf.read(buffer, 0, readLength)
                if (bytesRead <= 0) break
                output.write(buffer, 0, bytesRead)
                position += bytesRead
            }
            output.flush()
        }
    }

    private fun writeStatusOnly(output: OutputStream, code: Int, reason: String) {
        val response = "HTTP/1.1 $code $reason$CRLF" +
            "Connection: close$CRLF" +
            "Content-Length: 0$CRLF$CRLF"
        runCatching { output.write(response.toByteArray(Charsets.ISO_8859_1)); output.flush() }
    }
}
