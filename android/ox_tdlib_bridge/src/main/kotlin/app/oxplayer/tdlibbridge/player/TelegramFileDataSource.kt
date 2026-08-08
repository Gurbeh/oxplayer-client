package app.oxplayer.tdlibbridge.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import app.oxplayer.tdlibbridge.media.TdlibFileFetcher
import kotlinx.coroutines.runBlocking
import org.drinkless.tdlib.TdApi
import java.io.RandomAccessFile

/**
 * media3 DataSource reading directly from a TDLib-downloaded file, requesting bytes from TDLib
 * (TdApi.DownloadFile) as ExoPlayer reads/seeks rather than pre-downloading the whole file.
 * Preferred over a localhost HTTP loopback server (plan doc B.4) — more idiomatic media3
 * integration, no TCP/HTTP framing overhead, and this module is Android-only so there's no
 * cross-platform reason to force an HTTP layer.
 *
 * DataSource.read is a synchronous, off-main-thread call in media3's loading pipeline; blocking
 * here with runBlocking on TdlibFileFetcher's suspend functions is the correct fit (same shape as
 * any other synchronous DataSource backed by blocking I/O), not something to work around.
 */
@UnstableApi
class TelegramFileDataSource(
    private val fileFetcher: TdlibFileFetcher,
) : BaseDataSource(/* isNetwork= */ true) {

    private var randomAccessFile: RandomAccessFile? = null
    private var dataSpec: DataSpec? = null
    private var bytesRemaining: Long = 0
    private var currentFileId: Int = -1

    // Tracks the contiguous range TDLib has already confirmed available, so read() (called once
    // per small extractor chunk, sometimes tens of thousands of times per seek) only round-trips
    // into TDLib via awaitBytesAvailable when it's about to read past that range, instead of on
    // every call. Reproduced: a tight read loop over an already-downloaded prefix generated ~25k
    // GetFile requests in ~50s, which saturated TDLib's single request thread and stalled playback.
    private var knownAvailableUpTo: Long = 0
    private var fullyDownloaded: Boolean = false

    override fun open(dataSpec: DataSpec): Long {
        this.dataSpec = dataSpec
        transferInitializing(dataSpec)

        val fileId = fileIdFromUri(dataSpec.uri)
        currentFileId = fileId
        val position = dataSpec.position
        knownAvailableUpTo = 0
        fullyDownloaded = false

        val requestedLength = dataSpec.length.takeIf { it != C.LENGTH_UNSET.toLong() }
        val initialChunk = minOf(READ_AHEAD_BYTES, requestedLength ?: READ_AHEAD_BYTES)

        val file = runBlocking {
            fileFetcher.requestDownload(fileId, position, priority = 32)
            fileFetcher.awaitBytesAvailable(fileId, position, initialChunk)
        }
        updateAvailability(file)

        val raf = RandomAccessFile(file.local.path, "r")
        raf.seek(position)
        randomAccessFile = raf

        bytesRemaining = requestedLength ?: (file.size - position)

        transferStarted(dataSpec)
        return bytesRemaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (bytesRemaining == 0L) return C.RESULT_END_OF_INPUT

        val raf = randomAccessFile ?: error("TelegramFileDataSource.read called before open()")
        val position = raf.filePointer
        val readLength = minOf(length.toLong(), bytesRemaining).toInt()

        if (!fullyDownloaded && position + readLength > knownAvailableUpTo) {
            val file = runBlocking {
                fileFetcher.awaitBytesAvailable(currentFileId, position, readLength.toLong())
            }
            updateAvailability(file)
        }

        val bytesRead = raf.read(buffer, offset, readLength)
        if (bytesRead == -1) {
            return C.RESULT_END_OF_INPUT
        }
        bytesRemaining -= bytesRead
        bytesTransferred(bytesRead)
        return bytesRead
    }

    private fun updateAvailability(file: TdApi.File) {
        knownAvailableUpTo = file.local.downloadOffset + file.local.downloadedPrefixSize
        fullyDownloaded = file.local.isDownloadingCompleted
    }

    override fun getUri(): Uri? = dataSpec?.uri

    override fun close() {
        randomAccessFile?.let { runCatching { it.close() } }
        randomAccessFile = null
        // Deliberately does not cancel the TDLib download here — ExoPlayer opens/closes
        // DataSource instances more often than a playback session actually ends (e.g. internal
        // buffering resets). Download cancellation belongs to whoever owns the playback session
        // lifecycle (the Pigeon bridge's start/stopPlaybackSession), not this DataSource.
        transferEnded()
    }

    private fun fileIdFromUri(uri: Uri): Int {
        // Caller mints tdlib-file://{fileId} once TdlibChannelResolver has resolved the message
        // to a TdApi.File — see the Pigeon bridge's startPlaybackSession.
        return uri.host?.toIntOrNull()
            ?: uri.lastPathSegment?.toIntOrNull()
            ?: error("Invalid Telegram file uri: $uri (expected tdlib-file://{fileId})")
    }

    companion object {
        private const val READ_AHEAD_BYTES = 256L * 1024
    }

    @UnstableApi
    class Factory(private val fileFetcher: TdlibFileFetcher) : DataSource.Factory {
        override fun createDataSource(): DataSource = TelegramFileDataSource(fileFetcher)
    }
}
