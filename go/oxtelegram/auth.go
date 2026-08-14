package oxtelegram

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

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
	tg         *telegram.Client
	apiID      int
	apiHash    string
	sink       AuthEventSink
	dispatcher tg.UpdateDispatcher

	mu       sync.Mutex
	phone    string
	codeHash string
	qrCancel context.CancelFunc
	// loggedIn is signaled by UpdateLoginToken (QR accepted on phone). Created once;
	// RequestQrLogin always reads this same channel.
	loggedIn qrlogin.LoggedIn
	// botMode is set once SubmitBotToken succeeds. ResolveVideoFile reads it (via IsBotMode) to
	// decide whether it's safe to resolve a public channel directly (session accounts) or must
	// instead wait for the server's live-forwarded push (bot accounts — see Client.pushedDocs).
	botMode bool
}

// IsBotMode reports whether this session logged in via SubmitBotToken rather than
// phone/QR — see ResolveVideoFile.
func (a *AuthController) IsBotMode() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.botMode
}

func newAuthController(
	tgClient *telegram.Client,
	apiID int,
	apiHash string,
	sink AuthEventSink,
	dispatcher tg.UpdateDispatcher,
) *AuthController {
	a := &AuthController{
		tg:         tgClient,
		apiID:      apiID,
		apiHash:    apiHash,
		sink:       sink,
		dispatcher: dispatcher,
	}
	// Buffered so UpdateLoginToken is not dropped if it arrives between show() and select.
	ch := make(chan struct{}, 1)
	dispatcher.OnLoginToken(func(ctx context.Context, e tg.Entities, update *tg.UpdateLoginToken) error {
		println("ox-tdlib-auth: UpdateLoginToken received")
		select {
		case ch <- struct{}{}:
		default:
		}
		return nil
	})
	a.loggedIn = ch
	return a
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
		if self, err := a.tg.Self(ctx); err == nil && self != nil {
			a.mu.Lock()
			a.botMode = self.Bot
			a.mu.Unlock()
			if self.Bot {
				log.Printf("oxtelegram: restored BOT session id=%d @%s — getHistory/search are invalid; 0/0 play needs live push into this bot", self.ID, self.Username)
			} else {
				log.Printf("oxtelegram: restored USER session id=%d", self.ID)
			}
		}
		a.emit(AuthReady, "", "", "")
		return
	}
	a.emit(AuthWaitingForPhoneNumber, "", "", "")
}

// SubmitBotToken logs in as a bot (auth.importBotAuthorization) instead of a personal
// phone/QR account — the alternate login mode for users who don't want to give OXPlayer TDLib
// access to their real Telegram account. Confirmed working (no file-size cap, no FLOOD_WAIT
// across a full sequential+seek read of a 2.1GB file) against oxplayer-be's apps/bot2bot-poc
// spike before this was wired in. Goes straight from uninitialized/waitingForPhoneNumber to
// ready — there is no code/2FA step for bot login.
func (a *AuthController) SubmitBotToken(ctx context.Context, token string) error {
	_, err := a.tg.Auth().Bot(ctx, token)
	if err != nil {
		a.emit(AuthFailed, "", "", err.Error())
		return err
	}
	a.mu.Lock()
	a.botMode = true
	a.mu.Unlock()
	a.emit(AuthReady, "", "", "")
	return nil
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
	if isPasswordNeeded(err) {
		a.emit(AuthWaitingForPassword, "", "", "")
		return nil
	}
	a.emit(AuthFailed, "", "", err.Error())
	return err
}

func isPasswordNeeded(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, auth.ErrPasswordAuthNeeded) {
		return true
	}
	// Phone SignIn uses SESSION_PASSWORD_REQUIRED; QR Import often returns SESSION_PASSWORD_NEEDED.
	if tgerr.Is(err, "SESSION_PASSWORD_REQUIRED") || tgerr.Is(err, "SESSION_PASSWORD_NEEDED") {
		return true
	}
	msg := err.Error()
	return strings.Contains(msg, "SESSION_PASSWORD_NEEDED") ||
		strings.Contains(msg, "SESSION_PASSWORD_REQUIRED")
}

// SubmitTwoFactorPassword completes 2FA (step 3), reached from either the phone or QR flow.
// Wrong password stays on waitingForPassword — AuthFailed would send the TV UI back to the
// phone-number step (LoginPanel's default branch). Dart still receives the error via return.
func (a *AuthController) SubmitTwoFactorPassword(ctx context.Context, password string) error {
	_, err := a.tg.Auth().Password(ctx, password)
	if err != nil {
		if isInvalidPassword(err) {
			a.emit(AuthWaitingForPassword, "", "", "")
			return err
		}
		a.emit(AuthFailed, "", "", err.Error())
		return err
	}
	a.emit(AuthReady, "", "", "")
	return nil
}

func isInvalidPassword(err error) bool {
	if err == nil {
		return false
	}
	if tgerr.Is(err, "PASSWORD_HASH_INVALID") || tgerr.Is(err, "PASSWORD_EMPTY") {
		return true
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "password_hash_invalid") ||
		strings.Contains(msg, "invalid password") ||
		strings.Contains(msg, "password_empty")
}

// RequestQrLogin starts the QR login flow (Android TV path). Runs in its own goroutine.
//
// Uses telegram.Client.QR() (MigrateTo wired). Acceptance is detected via UpdateLoginToken
// and a 2s Import probe — NOT via repeated Export (each Export can mint a new token and
// invalidate the QR the user is mid-scan). Token refresh Export runs only on expiry.
func (a *AuthController) RequestQrLogin(ctx context.Context) error {
	qrCtx, cancel := context.WithCancel(ctx)
	a.mu.Lock()
	if a.qrCancel != nil {
		a.qrCancel()
	}
	a.qrCancel = cancel
	a.mu.Unlock()

	go a.runQrLogin(qrCtx)
	return nil
}

func (a *AuthController) runQrLogin(qrCtx context.Context) {
	qr := a.tg.QR()
	var token qrlogin.Token
	var expiry *time.Timer

	refreshToken := func(notice string) (ok bool) {
		t, err := qr.Export(qrCtx)
		if err != nil {
			_ = a.handleQrExportErr(err, func() {})
			return false
		}
		if t.Empty() {
			return false
		}
		token = t
		a.emit(AuthWaitingForQr, token.URL(), "", notice)
		if expiry != nil {
			expiry.Reset(tokenExpiresIn(token))
		}
		return true
	}

	tryImport := func() (done bool) {
		// Empty QR URL = "confirming" UI on the Flutter QR panel (scan accepted, Import running).
		a.emit(AuthWaitingForQr, "", "", "")
		_, err := qr.Import(qrCtx)
		if err != nil && isQrStillWaiting(err) {
			// Premature signal — restore previous QR for another attempt.
			if !token.Empty() {
				a.emit(AuthWaitingForQr, token.URL(), "", "")
			}
			return false
		}
		// Stale/expired token after scan — mint a fresh QR; do not AuthFailed (traps TV on spinner).
		if err != nil && isQrTokenExpired(err) {
			if !refreshToken("AUTH_TOKEN_EXPIRED") {
				a.emit(AuthFailed, "", "", err.Error())
				return true
			}
			return false
		}
		_ = a.handleSignInResult(err)
		return true
	}

	// Mirror gotd qrlogin.Auth timing: do not Export every few seconds (mints a new QR).
	// Acceptance: UpdateLoginToken and a probe that only reacts to MigrateTo/Success.
	exported, err := qr.Export(qrCtx)
	if err != nil {
		_ = a.handleQrExportErr(err, func() { _ = tryImport() })
		return
	}
	token = exported
	if token.Empty() {
		_ = tryImport()
		return
	}

	until := tokenExpiresIn(token)
	expiry = time.NewTimer(until)
	defer expiry.Stop()
	probe := time.NewTicker(2 * time.Second)
	defer probe.Stop()
	a.emit(AuthWaitingForQr, token.URL(), "", "")

	for {
		select {
		case <-qrCtx.Done():
			return
		case <-a.loggedIn:
			if tryImport() {
				return
			}
		case <-probe.C:
			// Probe without replacing the on-screen QR when still AuthLoginToken.
			result, err := a.tg.API().AuthExportLoginToken(qrCtx, &tg.AuthExportLoginTokenRequest{
				APIID:   a.apiID,
				APIHash: a.apiHash,
			})
			if err != nil {
				if errors.Is(err, context.Canceled) {
					return
				}
				if isPasswordNeeded(err) {
					a.emit(AuthWaitingForPassword, "", "", "")
					return
				}
				if isQrTokenExpired(err) {
					if !refreshToken("AUTH_TOKEN_EXPIRED") {
						return
					}
					continue
				}
				continue
			}
			switch result.(type) {
			case *tg.AuthLoginToken:
				// Still waiting — keep current QR even if server rotated the unused token.
				continue
			case *tg.AuthLoginTokenMigrateTo, *tg.AuthLoginTokenSuccess:
				if tryImport() {
					return
				}
			default:
				continue
			}
		case <-expiry.C:
			if !refreshToken("") {
				return
			}
		}
	}
}

func isQrTokenExpired(err error) bool {
	if err == nil {
		return false
	}
	if tgerr.Is(err, "AUTH_TOKEN_EXPIRED") || tgerr.Is(err, "AUTH_TOKEN_INVALID") {
		return true
	}
	msg := strings.ToUpper(err.Error())
	return strings.Contains(msg, "AUTH_TOKEN_EXPIRED") ||
		strings.Contains(msg, "AUTH_TOKEN_INVALID")
}

func tokenExpiresIn(token qrlogin.Token) time.Duration {
	until := time.Until(token.Expires()).Truncate(time.Second)
	if until < 5*time.Second {
		// Expires() missing/zero — Telegram tokens last ~30s; refresh slightly early.
		return 25 * time.Second
	}
	return until
}

func (a *AuthController) handleQrExportErr(err error, finishImport func()) bool {
	if errors.Is(err, context.Canceled) {
		return true
	}
	if isPasswordNeeded(err) {
		a.emit(AuthWaitingForPassword, "", "", "")
		return true
	}
	var mig *qrlogin.MigrationNeededError
	if errors.As(err, &mig) || isUnexpectedLoginTokenMigrate(err) {
		finishImport()
		return true
	}
	a.emit(AuthFailed, "", "", err.Error())
	return true
}

// isQrStillWaiting reports Import/Export "not accepted yet" (still *tg.AuthLoginToken).
func isQrStillWaiting(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "AuthLoginToken") &&
		!strings.Contains(msg, "AuthLoginTokenMigrateTo") &&
		!strings.Contains(msg, "AuthLoginTokenSuccess")
}

func isUnexpectedLoginTokenMigrate(err error) bool {
	if err == nil {
		return false
	}
	// gotd v0.132 Export: errors.Errorf("unexpected type %T", result) for MigrateTo.
	msg := err.Error()
	return strings.Contains(msg, "unexpected type") && strings.Contains(msg, "AuthLoginTokenMigrateTo")
}

// LogOut invalidates the session server-side. The caller is responsible for wiping local session
// storage afterward (mirrors TdlibBridgeObject.logOut's close-then-wipe ordering).
// DeadlineExceeded/Canceled are treated as success so OX UI logout does not hang ~30s.
func (a *AuthController) LogOut(ctx context.Context) error {
	a.emit(AuthLoggingOut, "", "", "")
	_, err := a.tg.API().AuthLogOut(ctx)
	a.emit(AuthClosed, "", "", "")
	if err != nil && (errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled)) {
		return nil
	}
	return err
}
