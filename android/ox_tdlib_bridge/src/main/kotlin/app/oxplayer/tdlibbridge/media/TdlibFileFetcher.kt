package app.oxplayer.tdlibbridge.media

import app.oxplayer.tdlibbridge.session.TdlibClient
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import org.drinkless.tdlib.TdApi

/**
 * Coordinates TdApi.DownloadFile/UpdateFile for a single playback session's file. TDLib's file
 * manager owns chunk alignment, CDN redirects, and flood-wait internally (see plan doc B.2/B.4) —
 * this class only needs to request the right (offset, limit) window and wait for enough bytes to
 * be locally available before handing a byte range back to the player (see TelegramFileDataSource).
 *
 * `TdApi.LocalFile.downloadOffset` + `downloadedPrefixSize` is TDLib's purpose-built mechanism for
 * exactly this range-download-for-streaming use case: bytes are guaranteed contiguously available
 * from `downloadOffset` up to `downloadOffset + downloadedPrefixSize`, which is what a seek needs.
 */
class TdlibFileFetcher(private val tdlibClient: TdlibClient) {

    /**
     * Requests download starting at [offset] bytes — used both for normal sequential playback
     * (offset 0, [limit] 0 = download to end) and for seeks (offset = the byte the player just
     * jumped to, which restarts the contiguous-availability window there rather than from 0).
     * [priority] 1-32, higher = more urgent; use a high priority for the range the player is
     * actively blocked on, a lower one for background read-ahead.
     */
    suspend fun requestDownload(
        fileId: Int,
        offset: Long,
        limit: Long = 0,
        priority: Int = 32,
    ): TdApi.File {
        return tdlibClient.send<TdApi.File>(TdApi.DownloadFile(fileId, priority, offset, limit, false))
    }

    /**
     * Suspends until at least [minBytesAvailable] contiguous bytes are available starting at
     * [offset], or the file's download otherwise goes idle (error, or download reached the end).
     * Callers (TelegramFileDataSource) call this before reading from `local.path` at [offset].
     */
    suspend fun awaitBytesAvailable(fileId: Int, offset: Long, minBytesAvailable: Long): TdApi.File {
        // Reproduced: a file already fully downloaded before this call (previously played, or
        // downloaded by an earlier session) satisfies the request immediately, but TDLib only
        // emits UpdateFile on a *change* in download state — since nothing changes for an
        // already-complete file, no event ever arrives and listening on the flow alone hangs
        // forever waiting for one. Check the current state up front via the offline GetFile call
        // before falling back to waiting for a future update.
        val current = tdlibClient.send<TdApi.File>(TdApi.GetFile(fileId))
        if (satisfiesRange(current, offset, minBytesAvailable)) return current

        return tdlibClient.updates
            .filterIsInstance<TdApi.UpdateFile>()
            .map { it.file }
            .filter { it.id == fileId }
            .first { satisfiesRange(it, offset, minBytesAvailable) }
    }

    private fun satisfiesRange(file: TdApi.File, offset: Long, minBytesAvailable: Long): Boolean {
        val local = file.local
        val haveEnough = local.downloadOffset <= offset &&
            (local.downloadOffset + local.downloadedPrefixSize) >= (offset + minBytesAvailable)
        return haveEnough || !local.isDownloadingActive
    }

    suspend fun cancelDownload(fileId: Int) {
        tdlibClient.send<TdApi.Ok>(TdApi.CancelDownloadFile(fileId, false))
    }
}
