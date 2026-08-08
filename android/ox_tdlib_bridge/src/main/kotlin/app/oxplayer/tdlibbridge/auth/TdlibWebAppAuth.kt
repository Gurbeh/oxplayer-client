package app.oxplayer.tdlibbridge.auth

import app.oxplayer.tdlibbridge.session.TdlibClient
import java.net.URI
import java.net.URLDecoder
import org.drinkless.tdlib.TdApi

class TelegramWebAppAuthException(message: String) : Exception(message)

/**
 * Fetches a Telegram-signed Mini App `initData` payload from TDLib (GetWebAppLinkUrl / GetWebAppUrl
 * / GetMainWebApp fallback chain) for exchange with the backend's `POST /auth/telegram`
 * (`auth_telegram_webapp.go`). Since TDLib is a genuine Telegram client, this signing happens
 * entirely on Telegram's own servers via the logged-in user's real session — no manual
 * bot-approval step, no raw session credential ever leaves the device.
 *
 * Requires a Mini App configured on the target bot via @BotFather (a short name, and/or a hosted
 * HTTPS Mini App URL, and/or a "Main Web App") — this is a Telegram-side bot configuration
 * prerequisite, not something code alone can satisfy. Ported from the sequence in
 * oxplayer-client's `oxplayer_telegram_td_session.dart` (native path), commit `6030a89c` — field
 * names/types re-verified against the actually-vendored TdApi.java (some TDLib API shapes shifted
 * since that commit's pin, e.g. `MainWebApp.url` is now a nested `WebAppUrl`, not a bare string).
 */
class TdlibWebAppAuth(private val tdlibClient: TdlibClient) {

    suspend fun fetchInitData(
        botUsername: String,
        webAppShortName: String?,
        hostedHttpsUrl: String?,
        applicationName: String = "oxplayer",
    ): String {
        if (botUsername.isBlank()) {
            throw TelegramWebAppAuthException("Bot username not configured")
        }
        val resolved = tdlibClient.send<TdApi.Chat>(TdApi.SearchPublicChat(botUsername))
        val chatType = resolved.type as? TdApi.ChatTypePrivate
            ?: throw TelegramWebAppAuthException("Cannot resolve bot username to a private chat")
        val botUserId = chatType.userId

        val privateChat = tdlibClient.send<TdApi.Chat>(TdApi.CreatePrivateChat(botUserId, false))
        val params = TdApi.WebAppOpenParameters(null, applicationName, null)

        var webAppUrl: String? = null
        var lastError: Throwable? = null

        if (!webAppShortName.isNullOrBlank()) {
            runCatching {
                tdlibClient.send<TdApi.WebAppUrl>(
                    TdApi.GetWebAppLinkUrl(
                        privateChat.id,
                        botUserId,
                        webAppShortName,
                        /* startParameter = */ "",
                        /* allowWriteAccess = */ true,
                        params,
                    ),
                )
            }.onSuccess { webAppUrl = it.url }.onFailure { lastError = it }
        }

        if (webAppUrl == null && !hostedHttpsUrl.isNullOrBlank()) {
            runCatching {
                tdlibClient.send<TdApi.WebAppUrl>(TdApi.GetWebAppUrl(botUserId, hostedHttpsUrl, params))
            }.onSuccess { webAppUrl = it.url }.onFailure { lastError = it }
        }

        if (webAppUrl == null) {
            runCatching {
                tdlibClient.send<TdApi.MainWebApp>(
                    TdApi.GetMainWebApp(privateChat.id, botUserId, webAppShortName ?: "", params),
                )
            }.onSuccess { webAppUrl = it.url.url }.onFailure { lastError = it }
        }

        val url = webAppUrl ?: throw TelegramWebAppAuthException(
            "Cannot get WebApp URL from Telegram" + (lastError?.message?.let { ": $it" } ?: ""),
        )

        return extractTgWebAppData(url)
            ?: throw TelegramWebAppAuthException("tgWebAppData not found in WebApp URL from Telegram")
    }

    private fun extractTgWebAppData(webAppUrl: String): String? {
        val uri = runCatching { URI(webAppUrl) }.getOrNull() ?: return null
        val fromQuery = extractQueryParam(uri.rawQuery, "tgWebAppData")
        if (!fromQuery.isNullOrEmpty()) return fromQuery
        val fragment = uri.rawFragment ?: return null
        val queryFromFragment = fragment.substringAfter('?', fragment)
        return extractQueryParam(queryFromFragment, "tgWebAppData")
    }

    private fun extractQueryParam(query: String?, key: String): String? {
        if (query.isNullOrEmpty()) return null
        for (pair in query.split("&")) {
            if (pair.isEmpty()) continue
            val eq = pair.indexOf('=')
            val rawKey = if (eq >= 0) pair.substring(0, eq) else pair
            val decodedKey = runCatching { URLDecoder.decode(rawKey, "UTF-8") }.getOrDefault(rawKey)
            if (decodedKey != key) continue
            val rawValue = if (eq >= 0) pair.substring(eq + 1) else ""
            return runCatching { URLDecoder.decode(rawValue, "UTF-8") }.getOrDefault(rawValue)
        }
        return null
    }
}
