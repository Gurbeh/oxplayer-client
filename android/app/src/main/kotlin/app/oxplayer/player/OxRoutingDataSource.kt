package app.oxplayer.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import app.oxplayer.objects.TdlibBridgeObject
import app.oxplayer.tdlibbridge.media.OxTelegramFileFetcher
import app.oxplayer.tdlibbridge.player.TelegramFileDataSource

/**
 * Routes ExoPlayer's DataSource.open by URI scheme: `tdlib-file://{fileId}` goes to
 * [TelegramFileDataSource] (bytes fetched live from the user's own Telegram session via the
 * gomobile-bound github.com/gotd/td facade, go/oxtelegram), anything else falls through to a
 * plain HTTP DataSource — used for subtitle delivery from the OX API, not for video. There is no
 * server-side video byte relay in this build: PlaybackInfo only ever mints `tdlib-file://` URIs
 * for video (see writePlaybackInfoOK / TELEGRAM_NATIVE_PLAYBACK_ENABLED), so the HTTP branch here
 * never serves video content.
 *
 * The delegate is looked up fresh on every [open] via [TdlibBridgeObject.fileFetcherFor] — keyed by
 * the fileId in the uri being opened, and never captured once: the underlying OxTelegramFileFetcher
 * is swapped out across login/logout and per playback session, so a composable-remember-captured
 * reference would go stale, and a "whichever is current" lookup would serve one play's bytes for
 * another play's uri.
 */
@UnstableApi
class OxRoutingDataSource(
    private val httpDataSourceFactory: DataSource.Factory,
) : DataSource {

    private val pendingListeners = mutableListOf<TransferListener>()
    private var delegate: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        val current = delegate
        if (current != null) {
            current.addTransferListener(transferListener)
        } else {
            pendingListeners.add(transferListener)
        }
    }

    override fun open(dataSpec: DataSpec): Long {
        val chosen = if (dataSpec.uri.scheme == TDLIB_FILE_SCHEME) {
            TelegramFileDataSource(resolveFetcher(dataSpec))
        } else {
            httpDataSourceFactory.createDataSource()
        }
        pendingListeners.forEach { chosen.addTransferListener(it) }
        delegate = chosen
        return chosen.open(dataSpec)
    }

    /**
     * The session that minted this exact uri, looked up by the fileId in it rather than by "which
     * session is current" — a stale uri must fail loudly, never quietly stream a different title's
     * bytes.
     *
     * The failure message distinguishes the two very different causes, because reporting the wrong
     * one sent TV users to re-login screens for a bug that had nothing to do with their login:
     * a missing Telegram auth really does need a login, while a missing session for a live login
     * means this playback's byte pipe was torn down and the url should have been re-resolved.
     */
    private fun resolveFetcher(dataSpec: DataSpec): OxTelegramFileFetcher {
        val fileId = dataSpec.uri.toString().substringAfterLast('/').toIntOrNull()
        if (fileId != null) {
            TdlibBridgeObject.fileFetcherFor(fileId)?.let { return it }
        }
        if (!TdlibBridgeObject.hasLiveAuth()) {
            error("No Telegram login for playback (log in with Telegram first)")
        }
        error(
            "Telegram playback session $fileId is no longer active (login is healthy; " +
                "the playback url outlived its session and must be re-resolved)",
        )
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val current = delegate ?: error("OxRoutingDataSource.read called before open()")
        return current.read(buffer, offset, length)
    }

    override fun getUri() = delegate?.uri

    override fun close() {
        delegate?.close()
        delegate = null
    }

    companion object {
        private const val TDLIB_FILE_SCHEME = "tdlib-file"
    }

    @UnstableApi
    class Factory(private val httpDataSourceFactory: DataSource.Factory) : DataSource.Factory {
        override fun createDataSource(): DataSource = OxRoutingDataSource(httpDataSourceFactory)
    }
}
