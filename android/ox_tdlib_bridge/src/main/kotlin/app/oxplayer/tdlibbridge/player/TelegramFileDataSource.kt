package app.oxplayer.tdlibbridge.player

import android.net.Uri
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import app.oxplayer.tdlibbridge.media.OxFileInfo
import app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher
import kotlinx.coroutines.runBlocking
import java.io.IOException
import java.io.RandomAccessFile
import java.util.concurrent.atomic.AtomicInteger

/**
 * media3 DataSource reading directly from a file downloaded on demand via the gotd/td-backed
 * facade (go/oxtelegram), as ExoPlayer reads/seeks rather than pre-downloading the whole file.
 */
@UnstableApi
class TelegramFileDataSource(
    private val fileFetcher: OxTelegramFileFetcher,
) : BaseDataSource(/* isNetwork= */ true) {

    private var randomAccessFile: RandomAccessFile? = null
    private var dataSpec: DataSpec? = null
    private var bytesRemaining: Long = 0
    private var currentFileId: Int = -1
    private var holdsStreamRef: Boolean = false
    /** True only after [transferStarted] — [transferEnded] must not run otherwise (NPE in BandwidthMeter). */
    private var transferOpen: Boolean = false

    // gotd/td exposes a single contiguous window [windowStart, windowEnd] that resets on
    // non-adjacent seek — NOT "everything from 0 to windowEnd".
    private var knownAvailableFrom: Long = 0
    private var knownAvailableUpTo: Long = 0
    private var fullyDownloaded: Boolean = false

    override fun open(dataSpec: DataSpec): Long {
        this.dataSpec = dataSpec
        transferInitializing(dataSpec)
        transferOpen = false

        val fileId = fileIdFromUri(dataSpec.uri)
        currentFileId = fileId
        val position = dataSpec.position
        knownAvailableFrom = 0
        knownAvailableUpTo = 0
        fullyDownloaded = false

        val requestedLength = dataSpec.length.takeIf { it != C.LENGTH_UNSET.toLong() }
        val initialChunk = minOf(READ_AHEAD_BYTES, requestedLength ?: READ_AHEAD_BYTES)

        activeStreams.incrementAndGet()
        holdsStreamRef = true

        val file = try {
            runBlocking {
                fileFetcher.requestDownload(fileId, position, priority = 32)
                fileFetcher.awaitBytesAvailable(fileId, position, initialChunk)
            }
        } catch (e: Exception) {
            releaseStreamRef()
            throw IOException("Telegram ensureAvailable failed at $position", e)
        }
        updateAvailability(file)

        if (!windowCovers(position, 1)) {
            Log.w(
                TAG,
                "open window miss fileId=$fileId position=$position " +
                    "window=[$knownAvailableFrom,$knownAvailableUpTo) — waiting again",
            )
            try {
                val retry = runBlocking {
                    fileFetcher.awaitBytesAvailable(fileId, position, initialChunk)
                }
                updateAvailability(retry)
            } catch (e: Exception) {
                releaseStreamRef()
                throw IOException("Telegram ensureAvailable retry failed at $position", e)
            }
        }
        if (!windowCovers(position, 1)) {
            Log.e(
                TAG,
                "open still uncovered fileId=$fileId position=$position " +
                    "window=[$knownAvailableFrom,$knownAvailableUpTo) — refusing sparse read",
            )
            releaseStreamRef()
            throw IOException(
                "Telegram bytes not available at $position " +
                    "(window=[$knownAvailableFrom,$knownAvailableUpTo))",
            )
        }

        val raf = RandomAccessFile(file.localPath, "r")
        raf.seek(position)
        randomAccessFile = raf

        bytesRemaining = requestedLength ?: (file.size - position)

        transferStarted(dataSpec)
        transferOpen = true
        Log.i(
            TAG,
            "open fileId=$fileId position=$position want=$initialChunk " +
                "window=[$knownAvailableFrom,$knownAvailableUpTo) size=${file.size} active=${activeStreams.get()}",
        )
        return bytesRemaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (bytesRemaining == 0L) return C.RESULT_END_OF_INPUT

        val raf = randomAccessFile ?: error("TelegramFileDataSource.read called before open()")
        val position = raf.filePointer
        val readLength = minOf(length.toLong(), bytesRemaining).toInt()

        if (!fullyDownloaded && !windowCovers(position, readLength.toLong())) {
            val file = runBlocking {
                fileFetcher.awaitBytesAvailable(currentFileId, position, readLength.toLong())
            }
            updateAvailability(file)
            if (!windowCovers(position, readLength.toLong())) {
                throw IOException(
                    "Telegram read uncovered at $position+$readLength " +
                        "(window=[$knownAvailableFrom,$knownAvailableUpTo))",
                )
            }
        }

        val bytesRead = raf.read(buffer, offset, readLength)
        if (bytesRead == -1) {
            return C.RESULT_END_OF_INPUT
        }
        bytesRemaining -= bytesRead
        bytesTransferred(bytesRead)
        return bytesRead
    }

    private fun windowCovers(position: Long, length: Long): Boolean {
        if (fullyDownloaded && knownAvailableFrom == 0L) return true
        return position >= knownAvailableFrom && position + length <= knownAvailableUpTo
    }

    private fun updateAvailability(file: OxFileInfo) {
        knownAvailableFrom = file.windowStart
        knownAvailableUpTo = file.windowEnd
        fullyDownloaded = file.isDownloadingCompleted && file.windowStart == 0L
    }

    override fun getUri(): Uri? = dataSpec?.uri

    override fun close() {
        randomAccessFile?.let { runCatching { it.close() } }
        randomAccessFile = null
        releaseStreamRef()
        if (transferOpen) {
            transferOpen = false
            transferEnded()
        }
    }

    private fun releaseStreamRef() {
        if (!holdsStreamRef) return
        holdsStreamRef = false
        // Do not cancelDownload when other DataSources still active (MKV cue + cluster).
        // Also: cancelling on every last-close races the next open's EnsureAvailable.
        if (activeStreams.decrementAndGet() <= 0) {
            // Leave in-flight bytes; session Close() on playback end cancels. Cancelling here
            // made cue→cluster handoff fail and killed startup after the complete-flag fix.
            Log.d(TAG, "last DataSource closed fileId=$currentFileId (download left running)")
        }
    }

    private fun fileIdFromUri(uri: Uri): Int {
        return uri.host?.toIntOrNull()
            ?: uri.lastPathSegment?.toIntOrNull()
            ?: error("Invalid Telegram file uri: $uri (expected tdlib-file://{fileId})")
    }

    companion object {
        private const val TAG = "OXPLAY_TDLIB"
        private const val READ_AHEAD_BYTES = 512L * 1024
        private val activeStreams = AtomicInteger(0)
    }

    @UnstableApi
    class Factory(private val fileFetcher: OxTelegramFileFetcher) : DataSource.Factory {
        override fun createDataSource(): DataSource = TelegramFileDataSource(fileFetcher)
    }
}
