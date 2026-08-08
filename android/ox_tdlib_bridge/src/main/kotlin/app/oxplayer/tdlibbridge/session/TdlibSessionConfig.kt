package app.oxplayer.tdlibbridge.session

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.SecureRandom
import org.drinkless.tdlib.TdApi

/**
 * Builds the [TdApi.SetTdlibParameters] request with the minimal-footprint config the direct-play
 * plan calls for (no chat list sync, no message database, no secret chats) and manages the
 * database_encryption_key TDLib uses to encrypt its local session directory at rest.
 *
 * TDLib does not talk to Android Keystore itself — it just wants raw key bytes on every launch.
 * So the actual random key lives in [EncryptedSharedPreferences] (Keystore-backed AES-GCM), and
 * we hand TDLib the decrypted bytes at process start. Losing this key makes the existing local
 * session unrecoverable (equivalent to a forced logout), which is the correct failure mode for a
 * lost encryption key, not something to work around.
 */
class TdlibSessionConfig(private val context: Context) {

    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFS_FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /** Returns the (Keystore-protected) database encryption key, generating one on first run. */
    fun databaseEncryptionKey(): ByteArray {
        val stored = prefs.getString(KEY_DB_ENCRYPTION_KEY, null)
        if (stored != null) {
            return Base64.decode(stored, Base64.NO_WRAP)
        }
        val fresh = ByteArray(32).also { SecureRandom().nextBytes(it) }
        prefs.edit().putString(KEY_DB_ENCRYPTION_KEY, Base64.encodeToString(fresh, Base64.NO_WRAP)).apply()
        return fresh
    }

    /** Wipes the stored encryption key. Call after TdApi.LogOut / TdApi.Destroy, not instead of it. */
    fun clearDatabaseEncryptionKey() {
        prefs.edit().remove(KEY_DB_ENCRYPTION_KEY).apply()
    }

    /**
     * Deletes the on-disk TDLib database/files. Required when rotating the encryption key
     * (QR abort → reset) — otherwise SetTdlibParameters fails against a DB encrypted with the
     * old key and auth never reaches WaitPhoneNumber.
     */
    fun wipeLocalDatabase() {
        val dbDir = context.getDir(TDLIB_DIR_NAME, Context.MODE_PRIVATE)
        if (dbDir.exists()) {
            dbDir.deleteRecursively()
        }
    }

    fun buildParameters(apiId: Int, apiHash: String): TdApi.SetTdlibParameters {
        val dbDir = context.getDir(TDLIB_DIR_NAME, Context.MODE_PRIVATE).absolutePath
        return TdApi.SetTdlibParameters().apply {
            this.apiId = apiId
            this.apiHash = apiHash
            databaseDirectory = dbDir
            filesDirectory = "$dbDir/files"
            databaseEncryptionKey = databaseEncryptionKey()

            // Minimal-footprint config (plan doc B.2/B.5): this module only ever needs to
            // resolve one public channel + one message + download one file per playback
            // session, never a live "Telegram client" event stream.
            useMessageDatabase = false
            // Reproduced against a real, chat-heavy account: with this off, every fresh
            // TdlibClient (i.e. every app restart) has no local chat list to diff against, so
            // reaching AuthorizationStateReady requires a FULL getDifference resync of every
            // chat — 90+ seconds and still climbing on a busy account, since there's nothing
            // incremental to catch up from. Chat *metadata* (not messages) persisted locally
            // lets subsequent reconnects diff incrementally instead of resyncing from zero.
            useChatInfoDatabase = true
            useFileDatabase = true // needed so DownloadFile progress/local-path tracking works
            useSecretChats = false
            useTestDc = false

            systemLanguageCode = "en"
            deviceModel = android.os.Build.MODEL ?: "Android"
            systemVersion = android.os.Build.VERSION.RELEASE ?: "unknown"
            applicationVersion = APPLICATION_VERSION
        }
    }

    companion object {
        private const val PREFS_FILE_NAME = "ox_tdlib_bridge_session"
        private const val KEY_DB_ENCRYPTION_KEY = "db_encryption_key"
        private const val TDLIB_DIR_NAME = "ox_tdlib_bridge_tdlib"
        // Bump alongside module changes that affect TDLib-visible client behavior; TDLib only
        // uses this for its own diagnostics, it does not gate protocol behavior.
        private const val APPLICATION_VERSION = "1.0"
    }
}
