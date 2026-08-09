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
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"

	"oxtelegram"
)

const callTimeout = 30 * time.Second

var (
	mu             sync.Mutex
	client         *oxtelegram.Client
	storage        *oxtelegram.DPAPISessionStorage
	bridge         *oxtelegram.HttpBridgeServer
	playback       *oxtelegram.DownloadSession
	playbackSource *oxtelegram.DownloadByteSource
	playbackFileID int
	playbackIDSeq  int
	playbackChan   string
	playbackMsgID  int64
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
	playbackChan = ""
	playbackMsgID = 0
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

//export ox_start_playback
func ox_start_playback(channel *C.char, messageID C.int64_t) *C.char {
	ch := C.GoString(channel)
	mid := int64(messageID)

	mu.Lock()
	// Subtitle/audio swap → Fladder shouldReload re-resolves t.me → must NOT tear down the
	// live HTTP bridge (MPV still reading the old URL). Reuse same session+URL.
	if playback != nil && playbackFileID != 0 && bridge != nil &&
		playbackChan == ch && playbackMsgID == mid {
		id := playbackFileID
		b := bridge
		mu.Unlock()
		url, err := b.URLFor(id)
		if err != nil {
			setErr(err)
			return nil
		}
		setErr(nil)
		return C.CString(url)
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
	ref, err := c.ResolveVideoFile(ctx, ch, mid)
	if err != nil {
		setErr(err)
		return nil
	}
	dl, err := c.OpenDownload(ref, dir)
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
	playbackChan = ch
	playbackMsgID = mid
	b.Register(id, src)
	mu.Unlock()

	url, err := b.URLFor(id)
	if err != nil {
		setErr(err)
		return nil
	}
	setErr(nil)
	return C.CString(url)
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
