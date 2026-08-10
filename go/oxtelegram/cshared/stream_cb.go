// stream_cb.go implements the C-ABI glue for libmpv's mpv_stream_cb_add_ro API
// (stream/stream_cb.h upstream, verified against
// https://github.com/mpv-player/mpv/blob/master/include/mpv/stream_cb.h). This lets mpv read
// Telegram bytes via direct in-process callbacks instead of the loopback HTTP bridge
// (http_bridge.go) — see C:\Users\Aryan\.claude\plans\prancy-rolling-kernighan.md's follow-on
// stream_cb plan for the full rationale.
//
// Dart registers the protocol itself: it calls mpv_stream_cb_add_ro(handle, "gotdstream", NULL,
// <address of ox_stream_open_fn>) directly against libmpv (obtained via media_kit's
// Player.handle), once per mpv_handle — every new mpv.Player instance (including the second
// player crossfade opens) needs its own registration call. This file only supplies the callback
// functions; it never calls into libmpv itself (calling libmpv APIs from inside a stream_cb
// callback deadlocks, per the header's own warning).
//
// All five stream callbacks are plain Go functions exported via cgo (//export) — NOT hand-written
// C. This is safe and standard cgo practice: a cgo-exported Go function has real C linkage and is
// callable as an ordinary C function pointer from any native thread, including ones the Go
// runtime did not create (mpv's internal demuxer/cache threads) — the Go runtime attaches a
// matching M lazily on first call. The one thing that must be pure C is the *assignment* of these
// exported functions' addresses into the mpv_stream_cb_info struct fields, since Go cannot take
// the address of a cgo-exported function as a value directly — ox_stream_fill_info below does
// that assignment in C, from forward declarations of the Go functions defined later in this file.
package main

/*
#include <stdint.h>

typedef int64_t (*mpv_stream_cb_read_fn)(void *cookie, char *buf, uint64_t nbytes);
typedef int64_t (*mpv_stream_cb_seek_fn)(void *cookie, int64_t offset);
typedef int64_t (*mpv_stream_cb_size_fn)(void *cookie);
typedef void (*mpv_stream_cb_close_fn)(void *cookie);
typedef void (*mpv_stream_cb_cancel_fn)(void *cookie);

typedef struct mpv_stream_cb_info {
	void *cookie;
	mpv_stream_cb_read_fn read_fn;
	mpv_stream_cb_seek_fn seek_fn;
	mpv_stream_cb_size_fn size_fn;
	mpv_stream_cb_close_fn close_fn;
	mpv_stream_cb_cancel_fn cancel_fn;
} mpv_stream_cb_info;

// Forward declarations of the Go functions exported further down this file — needed so
// ox_stream_fill_info can reference their addresses before cgo has generated _cgo_export.h.
// Signatures here must exactly match the //export'd Go function signatures below.
extern int64_t ox_stream_read_fn(void *cookie, char *buf, uint64_t nbytes);
extern int64_t ox_stream_seek_fn(void *cookie, int64_t offset);
extern int64_t ox_stream_size_fn(void *cookie);
extern void ox_stream_close_fn(void *cookie);
extern void ox_stream_cancel_fn(void *cookie);

static void ox_stream_fill_info(mpv_stream_cb_info *info, void *cookie) {
	info->cookie = cookie;
	info->read_fn = ox_stream_read_fn;
	info->seek_fn = ox_stream_seek_fn;
	info->size_fn = ox_stream_size_fn;
	info->close_fn = ox_stream_close_fn;
	info->cancel_fn = ox_stream_cancel_fn;
}
*/
import "C"

import (
	"fmt"
	"log"
	"runtime/cgo"
	"strconv"
	"strings"
	"unsafe"

	"oxtelegram"
)

// mpv error codes this file returns on failure paths — see
// https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h's mpv_error enum.
const (
	mpvErrorLoadingFailed = -13
	mpvErrorUnsupported   = -18
	mpvErrorGeneric       = -20
)

const streamProtocol = "gotdstream://"

// parseStreamID extracts the playback file ID from a "gotdstream://<id>" URI.
func parseStreamID(uri string) (int, bool) {
	if !strings.HasPrefix(uri, streamProtocol) {
		return 0, false
	}
	id, err := strconv.Atoi(strings.TrimPrefix(uri, streamProtocol))
	if err != nil {
		return 0, false
	}
	return id, true
}

// ox_stream_open_fn matches mpv_stream_cb_open_ro_fn's signature exactly
// (int (*)(void *user_data, char *uri, mpv_stream_cb_info *info)). Pass the address of this
// function (looked up by symbol name from Dart) as the open_fn argument to
// mpv_stream_cb_add_ro. Only one playback session is live at a time today (see
// closePlaybackLocked's single-session note in main.go) — id must match the currently registered
// playbackFileID.
//
//export ox_stream_open_fn
func ox_stream_open_fn(userData unsafe.Pointer, uri *C.char, info *C.mpv_stream_cb_info) C.int {
	uriStr := C.GoString(uri)
	log.Printf("oxtelegram: ox_stream_open_fn CALLED uri=%q", uriStr)
	id, ok := parseStreamID(uriStr)
	if !ok {
		log.Printf("oxtelegram: ox_stream_open_fn parseStreamID failed for uri=%q", uriStr)
		return C.int(mpvErrorLoadingFailed)
	}

	mu.Lock()
	src := playbackSource
	curID := playbackFileID
	mu.Unlock()
	if src == nil || id != curID {
		setErr(fmt.Errorf("ox_stream_open_fn: no active playback session for id %d", id))
		return C.int(mpvErrorLoadingFailed)
	}

	inst, err := oxtelegram.NewStreamInstance(src)
	if err != nil {
		setErr(err)
		return C.int(mpvErrorLoadingFailed)
	}

	h := cgo.NewHandle(inst)
	// go vet flags this uintptr->unsafe.Pointer conversion ("possible misuse of unsafe.Pointer"),
	// but it's the documented runtime/cgo.Handle pattern for smuggling a Go value through a C
	// void* opaquely: the C side never dereferences cookie, only passes it back verbatim to
	// streamInstanceFor, which converts it back to a Handle and never treats it as a real
	// pointer. Known, accepted false positive for this idiom.
	C.ox_stream_fill_info(info, unsafe.Pointer(uintptr(h))) //nolint:govet
	return 0
}

func streamInstanceFor(cookie unsafe.Pointer) (*oxtelegram.StreamInstance, bool) {
	h := cgo.Handle(uintptr(cookie))
	inst, ok := h.Value().(*oxtelegram.StreamInstance)
	return inst, ok
}

//export ox_stream_read_fn
func ox_stream_read_fn(cookie unsafe.Pointer, buf *C.char, nbytes C.uint64_t) C.int64_t {
	inst, ok := streamInstanceFor(cookie)
	if !ok {
		return -1
	}
	dst := unsafe.Slice((*byte)(unsafe.Pointer(buf)), int(nbytes))
	n, err := inst.Read(dst)
	if err != nil && n == 0 {
		return -1
	}
	return C.int64_t(n)
}

//export ox_stream_seek_fn
func ox_stream_seek_fn(cookie unsafe.Pointer, offset C.int64_t) C.int64_t {
	inst, ok := streamInstanceFor(cookie)
	if !ok {
		return C.int64_t(mpvErrorGeneric)
	}
	n, err := inst.Seek(int64(offset))
	if err != nil {
		return C.int64_t(mpvErrorUnsupported)
	}
	return C.int64_t(n)
}

//export ox_stream_size_fn
func ox_stream_size_fn(cookie unsafe.Pointer) C.int64_t {
	inst, ok := streamInstanceFor(cookie)
	if !ok {
		return C.int64_t(mpvErrorUnsupported)
	}
	return C.int64_t(inst.Size())
}

//export ox_stream_close_fn
func ox_stream_close_fn(cookie unsafe.Pointer) {
	h := cgo.Handle(uintptr(cookie))
	if inst, ok := h.Value().(*oxtelegram.StreamInstance); ok {
		inst.Close()
	}
	h.Delete()
}

// ox_stream_cancel_fn is called by mpv from a thread other than the one running
// read_fn/seek_fn specifically to interrupt a blocked call — must not block itself.
//
//export ox_stream_cancel_fn
func ox_stream_cancel_fn(cookie unsafe.Pointer) {
	if inst, ok := streamInstanceFor(cookie); ok {
		inst.Cancel()
	}
}
