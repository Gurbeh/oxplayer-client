package app.oxplayer.tdlibbridge.auth

import app.oxplayer.tdlibbridge.session.OxTelegramClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import mobile.AuthEventSink

/**
 * Drives the gotd/td facade's phone+code(+2FA) and QR login flows, translating AuthEventSink
 * callbacks into [TdlibAuthState] for TdlibBridgeObject's Pigeon mapper.
 */
class OxTelegramAuthController(private val client: OxTelegramClient) {
    private val _state = MutableStateFlow<TdlibAuthState>(TdlibAuthState.Uninitialized)
    val state: StateFlow<TdlibAuthState> = _state

    /** Pass to OxTelegramClient.configure() — updates [state] as the Go facade calls back. */
    val sink = AuthEventSink { kind, qrLoginUrl, passwordHint, errorMessage ->
        _state.value = when (kind) {
            "uninitialized" -> TdlibAuthState.Uninitialized
            "waitingForPhoneNumber" -> TdlibAuthState.WaitingForPhoneNumber
            "waitingForCode" -> TdlibAuthState.WaitingForCode
            "waitingForPassword" -> TdlibAuthState.WaitingForPassword(passwordHint)
            "waitingForQrConfirmation" -> TdlibAuthState.WaitingForQrConfirmation(
                qrLoginUrl.orEmpty(),
                errorMessage.orEmpty(),
            )
            "ready" -> TdlibAuthState.Ready
            "loggingOut" -> TdlibAuthState.LoggingOut
            "closed" -> TdlibAuthState.Closed
            "failed" -> TdlibAuthState.Failed(IllegalStateException(errorMessage))
            else -> TdlibAuthState.Failed(IllegalStateException("unknown auth state kind=$kind"))
        }
    }

    suspend fun submitPhoneNumber(phone: String) = client.submitPhoneNumber(phone)

    suspend fun submitCode(code: String) = client.submitCode(code)

    suspend fun submitTwoFactorPassword(password: String) = client.submitTwoFactorPassword(password)

    suspend fun requestQrLogin() = client.requestQrLogin()

    suspend fun logOut() = client.logOut()
}
