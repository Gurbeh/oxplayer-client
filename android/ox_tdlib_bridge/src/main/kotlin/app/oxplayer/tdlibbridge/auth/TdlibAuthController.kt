package app.oxplayer.tdlibbridge.auth

import app.oxplayer.tdlibbridge.session.TdlibClient
import app.oxplayer.tdlibbridge.session.TdlibSessionConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.launch
import org.drinkless.tdlib.TdApi

/**
 * UI-facing auth state, derived from TdApi.UpdateAuthorizationState. Kept intentionally small —
 * this module only supports the states relevant to logging a user's personal Telegram account
 * into the app for direct play, not a full client's auth surface (e.g. no bot-token flow here).
 */
sealed class TdlibAuthState {
    data object Uninitialized : TdlibAuthState()
    data object WaitingForPhoneNumber : TdlibAuthState()
    data class WaitingForCode(val codeInfo: TdApi.AuthenticationCodeInfo) : TdlibAuthState()
    data class WaitingForPassword(val hint: String) : TdlibAuthState()
    data class WaitingForQrConfirmation(val loginUrl: String) : TdlibAuthState()
    data object Ready : TdlibAuthState()
    data object LoggingOut : TdlibAuthState()
    data object Closed : TdlibAuthState()
    data class Failed(val error: Throwable) : TdlibAuthState()
}

/**
 * Drives TDLib's authorization state machine for phone+code(+2FA) (phone/tablet) and QR
 * (Android TV, remote typing is bad UX) login. One instance per [TdlibClient] instance.
 *
 * NOTE: state names/flow here (AuthorizationStateWaitTdlibParameters -> ... -> Ready) match
 * TDLib's long-standing Java binding shape where database_encryption_key is supplied directly on
 * SetTdlibParameters (no separate WaitEncryptionKey step). Verify against the vendored version
 * once the native TDLib artifact is wired in (see module README).
 */
class TdlibAuthController(
    private val tdlibClient: TdlibClient,
    private val sessionConfig: TdlibSessionConfig,
    private val apiId: Int,
    private val apiHash: String,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<TdlibAuthState>(TdlibAuthState.Uninitialized)
    val state: StateFlow<TdlibAuthState> = _state

    @Volatile
    private var tdlibParametersSent = false

    init {
        scope.launch {
            tdlibClient.updates
                .filterIsInstance<TdApi.UpdateAuthorizationState>()
                .collect { update -> onAuthorizationState(update.authorizationState) }
        }
        // First WaitTdlibParameters can race ahead of the collector; pull current state explicitly.
        scope.launch {
            runCatching {
                val current = tdlibClient.send<TdApi.AuthorizationState>(TdApi.GetAuthorizationState())
                onAuthorizationState(current)
            }.onFailure { _state.value = TdlibAuthState.Failed(it) }
        }
    }

    /** Pull current TDLib authorization state (covers hot-restart / missed first update). */
    suspend fun syncAuthorizationState() {
        val current = tdlibClient.send<TdApi.AuthorizationState>(TdApi.GetAuthorizationState())
        onAuthorizationState(current)
    }

    private suspend fun onAuthorizationState(authState: TdApi.AuthorizationState) {
        when (authState) {
            is TdApi.AuthorizationStateWaitTdlibParameters -> {
                if (tdlibParametersSent) return
                tdlibParametersSent = true
                runCatching {
                    tdlibClient.send<TdApi.Ok>(sessionConfig.buildParameters(apiId, apiHash))
                }.recoverCatching { first ->
                    // Stale DB after key rotation (QR abort / crash mid-reset).
                    if (first.message?.contains("Wrong database encryption key", ignoreCase = true) == true) {
                        sessionConfig.wipeLocalDatabase()
                        sessionConfig.clearDatabaseEncryptionKey()
                        tdlibClient.send<TdApi.Ok>(sessionConfig.buildParameters(apiId, apiHash))
                    } else {
                        throw first
                    }
                }.onFailure {
                    tdlibParametersSent = false
                    _state.value = TdlibAuthState.Failed(it)
                }
            }
            is TdApi.AuthorizationStateWaitPhoneNumber ->
                _state.value = TdlibAuthState.WaitingForPhoneNumber
            is TdApi.AuthorizationStateWaitCode ->
                _state.value = TdlibAuthState.WaitingForCode(authState.codeInfo)
            is TdApi.AuthorizationStateWaitPassword ->
                _state.value = TdlibAuthState.WaitingForPassword(authState.passwordHint)
            is TdApi.AuthorizationStateWaitOtherDeviceConfirmation ->
                _state.value = TdlibAuthState.WaitingForQrConfirmation(authState.link)
            is TdApi.AuthorizationStateReady ->
                _state.value = TdlibAuthState.Ready
            is TdApi.AuthorizationStateLoggingOut ->
                _state.value = TdlibAuthState.LoggingOut
            is TdApi.AuthorizationStateClosing -> {
                // No-op; wait for AuthorizationStateClosed.
            }
            is TdApi.AuthorizationStateClosed ->
                _state.value = TdlibAuthState.Closed
            else -> {
                // AuthorizationStateWaitOtherDeviceConfirmation / registration states not
                // expected for this module's scope (existing accounts only, no sign-up flow).
            }
        }
    }

    /** Phone/tablet flow, step 1. Expect state to move to WaitingForCode next. */
    suspend fun submitPhoneNumber(phoneNumber: String) {
        // Explicit settings: SMS/Telegram app only — no flash/missed-call side channel
        // (those can look like a second "code" to the user).
        val settings = TdApi.PhoneNumberAuthenticationSettings().apply {
            allowFlashCall = false
            allowMissedCall = false
            isCurrentPhoneNumber = false
            hasUnknownPhoneNumber = false
            allowSmsRetrieverApi = false
            firebaseAuthenticationSettings = null
            authenticationTokens = emptyArray()
        }
        tdlibClient.send<TdApi.Ok>(TdApi.SetAuthenticationPhoneNumber(phoneNumber, settings))
    }

    /** Phone/tablet flow, step 2. */
    suspend fun submitCode(code: String) {
        tdlibClient.send<TdApi.Ok>(TdApi.CheckAuthenticationCode(code))
    }

    /** Phone/tablet flow, step 3 — only when state is WaitingForPassword (account has 2FA). */
    suspend fun submitTwoFactorPassword(password: String) {
        tdlibClient.send<TdApi.Ok>(TdApi.CheckAuthenticationPassword(password))
    }

    /** Android TV flow: request a QR login token; UI renders state.loginUrl as a QR code. */
    suspend fun requestQrLogin() {
        tdlibClient.send<TdApi.Ok>(TdApi.RequestQrCodeAuthentication(LongArray(0)))
    }

    /** Server-side logout. Caller must close the client, then [TdlibSessionConfig.wipeLocalDatabase]. */
    suspend fun logOut() {
        runCatching { tdlibClient.send<TdApi.Ok>(TdApi.LogOut()) }
    }
}
