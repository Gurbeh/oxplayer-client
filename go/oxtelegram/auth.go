package oxtelegram

import (
	"context"
	"errors"
	"fmt"
	"sync"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/auth"
	"github.com/gotd/td/telegram/auth/qrlogin"
	"github.com/gotd/td/tg"
	"github.com/gotd/td/tgerr"
)

// AuthStateKind mirrors OxTdlibAuthStateKind (pigeons/tdlib_bridge.dart) string-for-string, so
// the Kotlin mapping in Phase 4 stays a 1:1 switch instead of a new translation table.
type AuthStateKind string

const (
	AuthUninitialized         AuthStateKind = "uninitialized"
	AuthWaitingForPhoneNumber AuthStateKind = "waitingForPhoneNumber"
	AuthWaitingForCode        AuthStateKind = "waitingForCode"
	AuthWaitingForPassword    AuthStateKind = "waitingForPassword"
	AuthWaitingForQr          AuthStateKind = "waitingForQrConfirmation"
	AuthReady                 AuthStateKind = "ready"
	AuthLoggingOut            AuthStateKind = "loggingOut"
	AuthClosed                AuthStateKind = "closed"
	AuthFailed                AuthStateKind = "failed"
)

// AuthEventSink receives push-style auth state notifications. gotd/td's own auth API is
// call/response, not push-based like TDLib's UpdateAuthorizationState — this interface exists so
// callers (Kotlin/Dart via gomobile, or a Windows FFI equivalent) can keep the same "listen for
// state changes" programming model they already have.
type AuthEventSink interface {
	OnAuthStateChanged(kind, qrLoginURL, passwordHint, errorMessage string)
}

// AuthController drives phone/code/2FA/QR login against a live telegram.Client and synthesizes
// AuthEventSink notifications from gotd/td's call/response auth API.
//
// The password/2FA step is intentionally ONE shared code path (handleSignInResult /
// SubmitTwoFactorPassword) reached from both the phone flow and the QR flow: gotd/td raises
// SESSION_PASSWORD_REQUIRED asynchronously after a QR scan on 2FA-enabled accounts, exactly like
// auth.ErrPasswordAuthNeeded after phone SignIn (see plan Phase 1 — this is a design requirement,
// not something to patch in later after Phase 6 device testing finds it).
type AuthController struct {
	tg      *telegram.Client
	apiID   int
	apiHash string
	sink    AuthEventSink

	mu       sync.Mutex
	phone    string
	codeHash string
	qrCancel context.CancelFunc
}

func newAuthController(tgClient *telegram.Client, apiID int, apiHash string, sink AuthEventSink) *AuthController {
	return &AuthController{tg: tgClient, apiID: apiID, apiHash: apiHash, sink: sink}
}

func (a *AuthController) emit(kind AuthStateKind, qrURL, hint, errMsg string) {
	a.sink.OnAuthStateChanged(string(kind), qrURL, hint, errMsg)
}

// checkInitialStatus runs once right after Configure to emit the correct starting state —
// mirrors TdlibAuthController's "pull current state explicitly, don't rely only on the first
// push" defensiveness, adapted to gotd/td's call/response model.
func (a *AuthController) checkInitialStatus(ctx context.Context) {
	status, err := a.tg.Auth().Status(ctx)
	if err != nil {
		a.emit(AuthFailed, "", "", err.Error())
		return
	}
	if status.Authorized {
		a.emit(AuthReady, "", "", "")
		return
	}
	a.emit(AuthWaitingForPhoneNumber, "", "", "")
}

// SubmitPhoneNumber starts the phone/code flow (step 1 of 2-3).
func (a *AuthController) SubmitPhoneNumber(ctx context.Context, phone string) error {
	sentCode, err := a.tg.Auth().SendCode(ctx, phone, auth.SendCodeOptions{})
	if err != nil {
		a.emit(AuthFailed, "", "", err.Error())
		return err
	}
	sc, ok := sentCode.(*tg.AuthSentCode)
	if !ok {
		err := fmt.Errorf("unexpected SentCode type %T", sentCode)
		a.emit(AuthFailed, "", "", err.Error())
		return err
	}

	a.mu.Lock()
	a.phone = phone
	a.codeHash = sc.PhoneCodeHash
	a.mu.Unlock()

	a.emit(AuthWaitingForCode, "", "", "")
	return nil
}

// SubmitCode completes phone/code sign-in (step 2). May transition to waitingForPassword instead
// of ready — see handleSignInResult.
func (a *AuthController) SubmitCode(ctx context.Context, code string) error {
	a.mu.Lock()
	phone, hash := a.phone, a.codeHash
	a.mu.Unlock()

	_, err := a.tg.Auth().SignIn(ctx, phone, code, hash)
	return a.handleSignInResult(err)
}

// handleSignInResult is the single shared landing point for "did this sign-in attempt need a
// 2FA password" — reused by both SubmitCode (phone flow) and RequestQrLogin's goroutine (QR
// flow). A password requirement is an expected state transition, not a failure: it returns nil
// and emits waitingForPassword rather than propagating an error to the caller.
func (a *AuthController) handleSignInResult(err error) error {
	if err == nil {
		a.emit(AuthReady, "", "", "")
		return nil
	}
	if errors.Is(err, auth.ErrPasswordAuthNeeded) || tgerr.Is(err, "SESSION_PASSWORD_REQUIRED") {
		a.emit(AuthWaitingForPassword, "", "", "")
		return nil
	}
	a.emit(AuthFailed, "", "", err.Error())
	return err
}

// SubmitTwoFactorPassword completes 2FA (step 3), reached from either the phone or QR flow.
func (a *AuthController) SubmitTwoFactorPassword(ctx context.Context, password string) error {
	_, err := a.tg.Auth().Password(ctx, password)
	if err != nil {
		a.emit(AuthFailed, "", "", err.Error())
		return err
	}
	a.emit(AuthReady, "", "", "")
	return nil
}

// RequestQrLogin starts the QR login flow (Android TV path). Runs in its own goroutine since
// qrlogin.QR.Auth blocks until scanned/expired/cancelled; each freshly (re)generated token fires
// an emit(waitingForQrConfirmation, ...) with the new tg://login?token=... URL for the caller to
// render as a QR code.
//
// No push-based "scanned" signal is wired up (would need a gotd/contrib-style update dispatcher,
// out of scope for Phase 1) — QR.Auth's own periodic token-refresh loop (every ~30s per
// Telegram's protocol) re-checks acceptance on each expiry instead, at the cost of up to ~30s
// added latency to detect a scan versus a live push. Functionally complete; a pure UX polish
// deferred as a follow-up, not a correctness gap.
func (a *AuthController) RequestQrLogin(ctx context.Context) error {
	qrCtx, cancel := context.WithCancel(ctx)
	a.mu.Lock()
	if a.qrCancel != nil {
		a.qrCancel()
	}
	a.qrCancel = cancel
	a.mu.Unlock()

	go func() {
		qr := qrlogin.NewQR(a.tg.API(), a.apiID, a.apiHash, qrlogin.Options{})
		neverFires := make(chan struct{})
		_, err := qr.Auth(qrCtx, qrlogin.LoggedIn(neverFires), func(showCtx context.Context, token qrlogin.Token) error {
			a.emit(AuthWaitingForQr, token.URL(), "", "")
			return nil
		})
		if err != nil {
			if errors.Is(err, context.Canceled) {
				return
			}
			if errors.Is(err, auth.ErrPasswordAuthNeeded) || tgerr.Is(err, "SESSION_PASSWORD_REQUIRED") {
				a.emit(AuthWaitingForPassword, "", "", "")
				return
			}
			a.emit(AuthFailed, "", "", err.Error())
			return
		}
		a.emit(AuthReady, "", "", "")
	}()
	return nil
}

// LogOut invalidates the session server-side. The caller is responsible for wiping local session
// storage afterward (mirrors TdlibBridgeObject.logOut's close-then-wipe ordering).
func (a *AuthController) LogOut(ctx context.Context) error {
	a.emit(AuthLoggingOut, "", "", "")
	_, err := a.tg.API().AuthLogOut(ctx)
	a.emit(AuthClosed, "", "", "")
	return err
}
