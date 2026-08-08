package app.oxplayer.tdlibbridge.session

import org.drinkless.tdlib.TdApi

/**
 * Trims TDLib's peripheral background CPU/network/storage bookkeeping for a playback-only client
 * — see https://core.telegram.org/tdlib/options for the full list. Every option here is callable
 * before authorization completes (per that page), so this can run immediately after
 * [TdlibClient.start], no need to wait for Ready.
 *
 * What this does NOT do: stop the account's real-time update stream (new messages, chat/group/
 * presence updates across every chat). There is no TDLib option for that — an authorized client
 * always receives the full update stream from the server; [useMessageDatabase]/[useChatInfoDatabase]
 * (see TdlibSessionConfig) only control whether that stream gets persisted locally, not whether
 * it's received and processed. Cutting that cost for real means not keeping a client open longer
 * than a playback session needs — a session-lifecycle change, not an option.
 */
suspend fun TdlibClient.applyMinimalFootprintOptions() {
    suspend fun setBool(name: String, value: Boolean) {
        runCatching { send<TdApi.Ok>(TdApi.SetOption(name, TdApi.OptionValueBoolean(value))) }
    }
    suspend fun setInt(name: String, value: Long) {
        runCatching { send<TdApi.Ok>(TdApi.SetOption(name, TdApi.OptionValueInteger(value))) }
    }

    setBool("disable_network_statistics", true)
    setBool("disable_persistent_network_statistics", true)
    setBool("disable_top_chats", true)
    setBool("ignore_inline_thumbnails", true)
    // Playback-only: no chat UI ever reads TDLib's own notification grouping.
    setInt("notification_group_count_max", 0)
    // Don't keep synced-but-unused messages resident longer than necessary (min accepted: 60s).
    setInt("message_unload_delay", 60)
}
