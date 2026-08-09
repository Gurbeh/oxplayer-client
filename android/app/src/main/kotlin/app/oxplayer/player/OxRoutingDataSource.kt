package app.oxplayer.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import app.oxplayer.objects.TdlibBridgeObject
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
 * The delegate is looked up fresh on every [open] via [TdlibBridgeObject.currentFileFetcher]
 * rather than captured once — the underlying OxTelegramFileFetcher instance is swapped out across
 * login/logout and per playback session, and a composable-remember-captured reference would go
 * stale.
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
            val fetcher = TdlibBridgeObject.currentFileFetcher()
                ?: error("No active TDLib session for playback (log in with Telegram first)")
            TelegramFileDataSource(fetcher)
        } else {
            httpDataSourceFactory.createDataSource()
        }
        pendingListeners.forEach { chosen.addTransferListener(it) }
        delegate = chosen
        return chosen.open(dataSpec)
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
