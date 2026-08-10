package app.oxplayer.tdlibbridge.auth

/**
 * UI-facing auth state shared by [OxTelegramAuthController] and the Pigeon mapper in
 * TdlibBridgeObject. Legacy name — backed by gotd/td, not TDLib.
 */
sealed class TdlibAuthState {
    data object Uninitialized : TdlibAuthState()
    data object WaitingForPhoneNumber : TdlibAuthState()
    data object WaitingForCode : TdlibAuthState()
    data class WaitingForPassword(val hint: String) : TdlibAuthState()
    data class WaitingForQrConfirmation(val loginUrl: String, val notice: String = "") : TdlibAuthState()
    data object Ready : TdlibAuthState()
    data object LoggingOut : TdlibAuthState()
    data object Closed : TdlibAuthState()
    data class Failed(val error: Throwable) : TdlibAuthState()
}
