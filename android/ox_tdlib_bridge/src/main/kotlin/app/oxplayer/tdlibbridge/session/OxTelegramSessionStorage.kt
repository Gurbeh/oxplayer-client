package app.oxplayer.tdlibbridge.session

import android.content.Context
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import mobile.SessionStorage

/**
 * Persists the gotd/td facade's one opaque session blob via EncryptedSharedPreferences
 * (Keystore-backed AES-GCM) — much simpler than TDLib's on-disk SQLite+binlog+separate-
 * encryption-key model, since gotd/td's session.Storage is just two methods moving one []byte.
 *
 * An empty/missing blob is the correct "no session yet" signal: gotd/td's session.Loader.Load
 * treats len(buf) == 0 as ErrNotFound (ordinary fresh-install state), so [load] returning an
 * empty ByteArray on first run needs no special-casing here.
 */
class OxTelegramSessionStorage(context: Context) : SessionStorage {

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

    override fun load(): ByteArray {
        val stored = prefs.getString(KEY_SESSION, null) ?: return ByteArray(0)
        return Base64.decode(stored, Base64.NO_WRAP)
    }

    override fun store(data: ByteArray) {
        prefs.edit().putString(KEY_SESSION, Base64.encodeToString(data, Base64.NO_WRAP)).apply()
    }

    /** Deletes the persisted session — call after LogOut, mirroring TdlibSessionConfig's wipe. */
    fun clear() {
        prefs.edit().remove(KEY_SESSION).apply()
    }

    companion object {
        private const val PREFS_FILE_NAME = "ox_telegram_session"
        private const val KEY_SESSION = "session_blob"
    }
}
