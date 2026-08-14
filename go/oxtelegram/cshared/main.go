// Package main builds oxtelegram.dll (c-shared) for Windows Flutter FFI.
//
//	go build -buildmode=c-shared -o oxtelegram.dll ./cshared
//
// Flat C ABI only — gotd/oxtelegram, no TDLib.
package main

/*
#include <stdint.h>
#include <stdlib.h>

typedef void (*ox_auth_sink)(const char* kind, const char* qr_login_url, const char* password_hint, const char* error_message);

static void ox_auth_sink_invoke(ox_auth_sink fn, const char* a, const char* b, const char* c, const char* d) {
	if (fn) fn(a, b, c, d);
}
*/
import "C"

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"oxtelegram"
)

const callTimeout = 30 * time.Second

// providerBotsSetupTimeout covers start+mute+archive across the whole sender list, each of which is
// several sequential MTProto round trips. Generous because this runs off the playback path, at app
// enter, and a partial run leaves some senders unprepared.
const providerBotsSetupTimeout = 90 * time.Second

var (
	mu             sync.Mutex
	client         *oxtelegram.Client
	storage        *oxtelegram.DPAPISessionStorage
	bridge         *oxtelegram.HttpBridgeServer
	playback       *oxtelegram.DownloadSession
	playbackSource *oxtelegram.DownloadByteSource
	playbackFileID int
	playbackIDSeq  int
	playbackBotID  int64
	playbackMsgID  int64
	playbackLoc    string
	cacheDir       string
	authKind       = "uninitialized"
	authQR         string
	authHint       string
	authErr        string
	lastErr        string
	authSinkFn     C.ox_auth_sink
)

type cSink struct{}

func (cSink) OnAuthStateChanged(kind, qr, hint, errMsg string) {
	mu.Lock()
	authKind, authQR, authHint, authErr = kind, qr, hint, errMsg
	fn := authSinkFn
	mu.Unlock()
	// Do NOT call Dart from this stack while Dart may be blocked inside ox_configure
	// (NativeCallable.listener + free races / isolate re-entrancy). Dart polls
	// ox_current_auth_* after configure and during waitUntilReadyForAuthInput.
	// Push notify only from a detached goroutine, and keep CStrings alive (small leak)
	// until a later replace — Dart copies immediately in the listener.
	if fn == nil {
		return
	}
	go notifyDartAuthSink(fn, kind, qr, hint, errMsg)
}

func notifyDartAuthSink(fn C.ox_auth_sink, kind, qr, hint, errMsg string) {
	ck := C.CString(kind)
	cq := C.CString(qr)
	ch := C.CString(hint)
	ce := C.CString(errMsg)
	C.ox_auth_sink_invoke(fn, ck, cq, ch, ce)
	// Intentionally not freeing: listener is async; Dart copies on its isolate later.
}

func setErr(err error) {
	if err == nil {
		lastErr = ""
		return
	}
	lastErr = err.Error()
}

//export ox_last_error
func ox_last_error() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(lastErr)
}

//export ox_free
func ox_free(p *C.char) {
	if p != nil {
		C.free(unsafe.Pointer(p))
	}
}

//export ox_configure
func ox_configure(apiID C.int, apiHash *C.char, sessionPath *C.char, cachePath *C.char, sink C.ox_auth_sink) C.int {
	hash := C.GoString(apiHash)
	sessPath := C.GoString(sessionPath)
	cache := C.GoString(cachePath)
	if cache == "" {
		cache = filepath.Join(filepath.Dir(sessPath), "oxtelegram-cache")
	}
	_ = os.MkdirAll(cache, 0o700)

	mu.Lock()
	authSinkFn = sink
	cacheDir = cache
	if client != nil {
		mu.Unlock()
		setErr(nil)
		return 0
	}
	storage = oxtelegram.NewDPAPISessionStorage(sessPath)
	client = oxtelegram.NewClient(int(apiID), hash, storage)
	bridge = oxtelegram.NewHttpBridgeServer()
	c := client
	mu.Unlock()

	// Must NOT hold mu across Configure: checkInitialStatus → emit → OnAuthStateChanged
	// takes mu (deadlock). Also must return to Dart before relying on sink.
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	if err := c.Configure(ctx, cSink{}); err != nil {
		mu.Lock()
		client = nil
		storage = nil
		bridge = nil
		mu.Unlock()
		setErr(err)
		return 1
	}
	setErr(nil)
	return 0
}

//export ox_current_auth_kind
func ox_current_auth_kind() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(authKind)
}

//export ox_current_auth_qr
func ox_current_auth_qr() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(authQR)
}

//export ox_current_auth_hint
func ox_current_auth_hint() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(authHint)
}

//export ox_current_auth_error
func ox_current_auth_error() *C.char {
	mu.Lock()
	defer mu.Unlock()
	return C.CString(authErr)
}

func withAuth(fn func(*oxtelegram.AuthController) error) C.int {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil || c.Auth == nil {
		setErr(fmt.Errorf("oxtelegram not configured"))
		return 1
	}
	if err := fn(c.Auth); err != nil {
		setErr(err)
		return 1
	}
	setErr(nil)
	return 0
}

//export ox_submit_phone
func ox_submit_phone(phone *C.char) C.int {
	p := C.GoString(phone)
	return withAuth(func(a *oxtelegram.AuthController) error {
		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()
		return a.SubmitPhoneNumber(ctx, p)
	})
}

//export ox_submit_bot_token
func ox_submit_bot_token(token *C.char) C.int {
	v := C.GoString(token)
	return withAuth(func(a *oxtelegram.AuthController) error {
		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()
		return a.SubmitBotToken(ctx, v)
	})
}

//export ox_submit_code
func ox_submit_code(code *C.char) C.int {
	v := C.GoString(code)
	return withAuth(func(a *oxtelegram.AuthController) error {
		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()
		return a.SubmitCode(ctx, v)
	})
}

//export ox_submit_password
func ox_submit_password(password *C.char) C.int {
	v := C.GoString(password)
	return withAuth(func(a *oxtelegram.AuthController) error {
		ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
		defer cancel()
		return a.SubmitTwoFactorPassword(ctx, v)
	})
}

//export ox_request_qr
func ox_request_qr() C.int {
	return withAuth(func(a *oxtelegram.AuthController) error {
		return a.RequestQrLogin(context.Background())
	})
}

func closePlaybackLocked() {
	if playbackFileID != 0 && bridge != nil {
		bridge.Unregister(playbackFileID)
	}
	if playbackSource != nil {
		playbackSource.CancelCurrentRead()
	}
	if playback != nil {
		playback.Cancel()
		playback = nil
	}
	playbackSource = nil
	playbackFileID = 0
	playbackBotID = 0
	playbackMsgID = 0
	playbackLoc = ""
}

//export ox_logout
func ox_logout() C.int {
	mu.Lock()
	c := client
	st := storage
	closePlaybackLocked()
	client = nil
	mu.Unlock()
	if c != nil {
		if c.Auth != nil {
			ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
			_ = c.Auth.LogOut(ctx)
			cancel()
		}
		_ = c.Close()
	}
	if st != nil {
		_ = st.Clear()
	}
	mu.Lock()
	authKind = "uninitialized"
	authQR, authHint, authErr = "", "", ""
	mu.Unlock()
	setErr(nil)
	return 0
}

// providerBotID/messageID come from the PlaybackInfo Path (oxplayer-tg://{botId}/{msgId}); both are
// 0 when the backend has nothing remembered and a fresh copy is in flight, in which case locator —
// the ?loc= query param — is what identifies the incoming copy. See
// oxtelegram.Client.ResolveVideoFile.
//
//export ox_start_playback
func ox_start_playback(providerBotID C.int64_t, messageID C.int64_t, locatorC *C.char) *C.char {
	botID := int64(providerBotID)
	mid := int64(messageID)
	locator := C.GoString(locatorC)

	mu.Lock()
	// Subtitle/audio swap → Fladder shouldReload re-resolves the Path → must NOT tear down the
	// live session (mpv's stream_cb instance is still reading it). Reuse same session+URL.
	//
	// Matched on locator, not on bot+message id: those are 0/0 on a cold play, so keying on them
	// would make two resolves of the same in-flight delivery look identical and collide.
	//
	// The returned string is discarded by the Dart caller (see
	// oxplayer_telegram_windows_bridge.dart: it only checks the pointer for null, then frees it
	// and separately calls ox_stream_uri_for_current_playback for the real gotdstream:// URL) —
	// so this must be a valid non-null string, but never bridge.URLFor's HTTP loopback URL:
	// URLFor() lazily binds a real TCP listener via EnsureStarted(), and stream_cb has fully
	// replaced that transport, so calling it here would open an idle socket every playback for
	// no reason.
	if playback != nil && playbackFileID != 0 && locator != "" && playbackLoc == locator {
		id := playbackFileID
		mu.Unlock()
		setErr(nil)
		return C.CString(fmt.Sprintf("%s%d", streamProtocol, id))
	}
	c := client
	b := bridge
	dir := cacheDir
	mu.Unlock()
	if c == nil || b == nil {
		setErr(fmt.Errorf("oxtelegram not configured"))
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	ref, err := c.ResolveVideoFile(ctx, botID, mid, locator)
	if err != nil {
		setErr(err)
		return nil
	}
	// See mobile/bind.go's StartPlaybackSession: a cold resolve only learns its DM message id from
	// the live push, and that id is what refreshFileReference re-resolves against.
	if mid <= 0 {
		if learned := c.DeliveryRefForLocator(locator); learned.MessageID > 0 {
			mid = learned.MessageID
			botID = learned.ProviderBotID
		}
	}
	dl, err := c.OpenDownload(ref, mid, locator, dir)
	if err != nil {
		setErr(err)
		return nil
	}
	src := oxtelegram.NewDownloadByteSource(dl)

	mu.Lock()
	closePlaybackLocked()
	playbackIDSeq++
	id := playbackIDSeq
	playback = dl
	playbackSource = src
	playbackFileID = id
	playbackBotID = botID
	playbackMsgID = mid
	playbackLoc = locator
	b.Register(id, src)
	mu.Unlock()

	setErr(nil)
	return C.CString(fmt.Sprintf("%s%d", streamProtocol, id))
}

// ox_stream_uri_for_current_playback returns "gotdstream://<id>" for the currently active
// playback session set up by ox_start_playback (or NULL if none) — the URL to hand mpv's
// loadfile when using the stream_cb path (see stream_cb.go) instead of ox_start_playback's HTTP
// loopback URL. Both point at the same registered session; callers pick one transport per
// mpv.Player, they are not meant to be mixed for a single load.
//
//export ox_stream_uri_for_current_playback
func ox_stream_uri_for_current_playback() *C.char {
	mu.Lock()
	id := playbackFileID
	mu.Unlock()
	if id == 0 {
		setErr(fmt.Errorf("no active playback session"))
		return nil
	}
	setErr(nil)
	return C.CString(fmt.Sprintf("%s%d", streamProtocol, id))
}

// ox_delivery_message_id_for_locator returns the DM message id this session read for locator, or 0.
// Pairs with ox_delivery_provider_bot_id_for_locator: the Dart caller reports both to the backend
// (POST /me/telegram-delivery) so the next play of the same file needs no Telegram copy at all.
// Only the receiving side can know either — private-chat ids are numbered per side, and the server
// round-robins across senders so it does not know which one won.
//
//export ox_delivery_message_id_for_locator
func ox_delivery_message_id_for_locator(locatorC *C.char) C.int64_t {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		return 0
	}
	return C.int64_t(c.DeliveryRefForLocator(C.GoString(locatorC)).MessageID)
}

// ox_delivery_provider_bot_id_for_locator returns the delivery bot whose DM held locator, or 0.
//
//export ox_delivery_provider_bot_id_for_locator
func ox_delivery_provider_bot_id_for_locator(locatorC *C.char) C.int64_t {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		return 0
	}
	return C.int64_t(c.DeliveryRefForLocator(C.GoString(locatorC)).ProviderBotID)
}

// ox_arm_delivery_waiter registers interest in locator before the delivery request is sent, so a
// copy that arrives while PlaybackInfo is still in flight is captured rather than raced for.
//
//export ox_arm_delivery_waiter
func ox_arm_delivery_waiter(locatorC *C.char) {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		return
	}
	c.ArmDeliveryWaiter(C.GoString(locatorC))
}

// ox_warm_delivery resolves the delivery message and records its id WITHOUT opening a download —
// the warm-up path. Scrolling the dashboard warms a dozen titles at once, and starting a dozen
// progressive downloads for videos nobody pressed play on would spend the user's data on bytes that
// get thrown away. Resolving is enough: it makes the backend remember the id.
//
// Returns 0 on success, 1 on failure — the same convention as withAuth and every other status
// export here (ox_last_error carries the detail).
//
//export ox_warm_delivery
func ox_warm_delivery(providerBotID C.int64_t, messageID C.int64_t, locatorC *C.char) C.int {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		setErr(fmt.Errorf("oxtelegram not configured"))
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	if _, err := c.ResolveVideoFile(ctx, int64(providerBotID), int64(messageID), C.GoString(locatorC)); err != nil {
		setErr(err)
		return 1
	}
	setErr(nil)
	return 0
}

// ox_ensure_provider_bots_ready starts, mutes and archives every delivery sender on this account so
// delivery copies never land in the user's visible inbox. botsJSON is the array returned by the
// backend's GET /telegram/provider-bots: [{"id":123,"username":"SomeBot"}].
//
// Returns 0 on success, 1 on failure — same convention as the other status exports.
//
//export ox_ensure_provider_bots_ready
func ox_ensure_provider_bots_ready(botsJSON *C.char) C.int {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		setErr(fmt.Errorf("oxtelegram not configured"))
		return 1
	}
	var bots []oxtelegram.ProviderBot
	if err := json.Unmarshal([]byte(C.GoString(botsJSON)), &bots); err != nil {
		setErr(fmt.Errorf("parse provider bots: %w", err))
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), providerBotsSetupTimeout)
	defer cancel()
	if err := c.EnsureProviderBotsReady(ctx, bots); err != nil {
		setErr(err)
		return 1
	}
	setErr(nil)
	return 0
}

//export ox_stop_playback
func ox_stop_playback(sessionURI *C.char) C.int {
	// Only tear down the progressive download / HTTP registration — keep the Telegram
	// client logged in so the next play (or subtitle shouldReload) does not re-auth.
	//
	// IMPORTANT: honor sessionURI. loadPlaybackItem → stop() passes the *previous* episode's
	// bridge URL after createPlaybackModel already opened the *next* session. Closing blindly
	// kills the new episode → MPV 404 → forever loading.
	uri := C.GoString(sessionURI)
	mu.Lock()
	defer mu.Unlock()
	if playbackFileID == 0 || bridge == nil {
		setErr(nil)
		return 0
	}
	current, err := bridge.URLFor(playbackFileID)
	if err != nil {
		closePlaybackLocked()
		setErr(nil)
		return 0
	}
	if uri != "" && uri != current && !oxtelegram.SessionURIRefersToFile(uri, playbackFileID) {
		setErr(nil)
		return 0
	}
	closePlaybackLocked()
	setErr(nil)
	return 0
}

//export ox_fetch_webapp_init_data
func ox_fetch_webapp_init_data(bot *C.char, shortName *C.char, hostedURL *C.char, platform *C.char) *C.char {
	mu.Lock()
	c := client
	mu.Unlock()
	if c == nil {
		setErr(fmt.Errorf("oxtelegram not configured"))
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
	defer cancel()
	data, err := c.FetchWebAppInitData(ctx, C.GoString(bot), C.GoString(shortName), C.GoString(hostedURL), C.GoString(platform))
	if err != nil {
		setErr(err)
		return nil
	}
	setErr(nil)
	return C.CString(data)
}

func main() {}
