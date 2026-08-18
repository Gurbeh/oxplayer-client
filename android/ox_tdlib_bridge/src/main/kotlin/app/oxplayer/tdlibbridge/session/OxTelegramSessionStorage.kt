package app.oxplayer.tdlibbridge.session

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import mobile.SessionStorage
import java.io.File

/**
 * Persists the gotd/td facade's one opaque session blob via EncryptedSharedPreferences
 * (Keystore-backed AES-GCM) — much simpler than TDLib's on-disk SQLite+binlog+separate-
 * encryption-key model, since gotd/td's session.Storage is just two methods moving one []byte.
 *
 * An empty/missing blob is the correct "no session yet" signal: gotd/td's session.Loader.Load
 * treats len(buf) == 0 as ErrNotFound (ordinary fresh-install state), so [load] returning an
 * empty ByteArray on first run needs no special-casing here.
 *
 * Also writes [filesDir]/ox_telegram_session.bin. Some Android TVs drop EncryptedSharedPreferences
 * (or the Keystore master key) on `adb install -r`, which forced QR login after every rebuild.
 */
class OxTelegramSessionStorage(context: Context) : SessionStorage {

    private val appContext = context.applicationContext
    private val backupFile = File(appContext.filesDir, BACKUP_FILE_NAME)

    private val prefs by lazy {
        val masterKey = MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            appContext,
            PREFS_FILE_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override fun load(): ByteArray {
        loadFromPrefs()?.let { return it }
        return loadFromBackup()
    }

    override fun store(data: ByteArray) {
        runCatching {
            prefs.edit().putString(KEY_SESSION, Base64.encodeToString(data, Base64.NO_WRAP)).apply()
        }.onFailure { err ->
            Log.w(TAG, "encrypted session prefs write failed", err)
        }
        runCatching {
            backupFile.writeBytes(data)
        }.onFailure { err ->
            Log.w(TAG, "session backup write failed", err)
        }
    }

    /** Deletes the persisted session — call after LogOut, mirroring TdlibSessionConfig's wipe. */
    fun clear() {
        runCatching { prefs.edit().remove(KEY_SESSION).apply() }
        runCatching { if (backupFile.exists()) backupFile.delete() }
    }

    private fun loadFromPrefs(): ByteArray? {
        return try {
            val stored = prefs.getString(KEY_SESSION, null) ?: return null
            Base64.decode(stored, Base64.NO_WRAP)
        } catch (t: Throwable) {
            Log.w(TAG, "encrypted session prefs unreadable", t)
            null
        }
    }

    private fun loadFromBackup(): ByteArray {
        return try {
            if (!backupFile.exists() || backupFile.length() == 0L) ByteArray(0)
            else backupFile.readBytes()
        } catch (t: Throwable) {
            Log.w(TAG, "session backup unreadable", t)
            ByteArray(0)
        }
    }

    companion object {
        private const val TAG = "OXPLAY_TDLIB"
        private const val PREFS_FILE_NAME = "ox_telegram_session"
        private const val KEY_SESSION = "session_blob"
        private const val BACKUP_FILE_NAME = "ox_telegram_session.bin"
    }
}
