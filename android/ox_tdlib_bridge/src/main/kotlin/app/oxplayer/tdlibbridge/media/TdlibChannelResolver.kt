package app.oxplayer.tdlibbridge.media

import android.util.Log
import app.oxplayer.tdlibbridge.session.TdlibClient
import org.drinkless.tdlib.TdApi

private const val LOG_TAG = "OXPLAY_TDLIB"

class TelegramMediaNotFoundException(message: String) : Exception(message)

/**
 * Resolves a public provider channel (by @username, no membership required — this is how
 * PlaybackInfo's `TelegramChannelUsername`/`TelegramMessageId` fields get turned into an actual
 * downloadable file) and extracts the video file from the target message.
 */
class TdlibChannelResolver(private val tdlibClient: TdlibClient) {

    /**
     * SearchPublicChat + GetMessage works on a public channel without the account ever joining it
     * (confirmed: joining is not required, the earlier "Not Found" was the message-id encoding —
     * see [resolveMessage]). Deliberately does NOT call JoinChat: the user's account must not show
     * up as a member/subscriber of the provider channel just because they played something.
     * OpenChat only registers local sync state for this session — it adds no membership.
     */
    suspend fun resolveChat(username: String): TdApi.Chat {
        val cleanUsername = username.removePrefix("@").trim()
        Log.i(LOG_TAG, "resolveChat SearchPublicChat username=$cleanUsername (sending)")
        val chat = tdlibClient.send<TdApi.Chat>(TdApi.SearchPublicChat(cleanUsername))
        Log.i(LOG_TAG, "resolveChat SearchPublicChat username=$cleanUsername -> chatId=${chat.id}")
        runCatching { tdlibClient.send<TdApi.Ok>(TdApi.OpenChat(chat.id)) }
        return chat
    }

    /**
     * [messageId] is the raw server-side id — the same number that appears in a `t.me/{username}/{id}`
     * link (and in PlaybackInfo's TelegramMessageId, and in the Bot API). TDLib's own message ids
     * are NOT that number: internally every id is `serverMessageId shl MESSAGE_ID_SHIFT`, reserving
     * the low 20 bits for locally-generated (not-yet-sent) message ids. Passing the raw id straight
     * through — what this did before this fix — makes TDLib read it as a tiny local/unsent message
     * id that doesn't exist, so GetMessage always fails "Not Found" regardless of whether the real
     * message exists (reproduced against messages copied under a second earlier).
     */
    suspend fun resolveMessage(chatId: Long, messageId: Long): TdApi.Message {
        Log.i(LOG_TAG, "resolveMessage GetMessage chatId=$chatId messageId=$messageId (sending)")
        val message = tdlibClient.send<TdApi.Message>(TdApi.GetMessage(chatId, messageId shl MESSAGE_ID_SHIFT))
        Log.i(LOG_TAG, "resolveMessage GetMessage chatId=$chatId messageId=$messageId -> ok")
        return message
    }

    private companion object {
        const val MESSAGE_ID_SHIFT = 20
    }

    /** Extracts the downloadable TdApi.File from a message's video or document content. */
    fun videoFileFrom(message: TdApi.Message): TdApi.File {
        return when (val content = message.content) {
            is TdApi.MessageVideo -> content.video.video
            is TdApi.MessageDocument -> content.document.document
            else -> throw TelegramMediaNotFoundException(
                "Message ${message.id} in chat ${message.chatId} has no video/document content " +
                    "(${content::class.simpleName})",
            )
        }
    }

    /** One-shot resolve: username + message id -> the TdApi.File to download. */
    suspend fun resolveVideoFile(username: String, messageId: Long): TdApi.File {
        val chat = resolveChat(username)
        val message = resolveMessage(chat.id, messageId)
        return videoFileFrom(message)
    }
}
