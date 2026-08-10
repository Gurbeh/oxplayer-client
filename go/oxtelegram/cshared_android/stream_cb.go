//go:build android

// stream_cb.go is the Android port of cshared/stream_cb.go (Windows) — same mpv_stream_cb_info
// ABI, same "cgo-exported Go functions used directly as C function pointers" approach, verified
// against the same upstream https://github.com/mpv-player/mpv/blob/master/include/mpv/stream_cb.h.
// See that file's header comment for the full rationale; only what differs on Android is noted
// here.
//
// ox_stream_open_fn resolves the uri's id to a jniByteSource (jni_bridge.go) and wraps it in the
// same oxtelegram.StreamInstance Windows uses — see main.go's STATUS note on what's proven
// (builds + exports correctly) versus not yet (a real on-device JNI round-trip).
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
	"runtime/cgo"
	"strconv"
	"strings"
	"unsafe"

	"oxtelegram"
)

const (
	mpvErrorLoadingFailed = -13
	mpvErrorUnsupported   = -18
	mpvErrorGeneric       = -20
)

const streamProtocol = "gotdstream://"

// parseStreamID extracts the playback file ID from a "gotdstream://<id>" URI — same format and
// same id namespace as Windows's cshared/stream_cb.go, except here the id is minted by Kotlin's
// OxTelegramStreamBridge.registerSession, not by this .so.
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

//export ox_stream_open_fn
func ox_stream_open_fn(userData unsafe.Pointer, uri *C.char, info *C.mpv_stream_cb_info) C.int {
	id, ok := parseStreamID(C.GoString(uri))
	if !ok {
		return C.int(mpvErrorLoadingFailed)
	}

	src, err := newJNIByteSource(id)
	if err != nil {
		return C.int(mpvErrorLoadingFailed)
	}
	inst, err := oxtelegram.NewStreamInstance(src)
	if err != nil {
		return C.int(mpvErrorLoadingFailed)
	}

	h := cgo.NewHandle(inst)
	// See cshared/stream_cb.go's identical line for why this uintptr->unsafe.Pointer conversion
	// (flagged by go vet as a possible misuse) is the correct, documented runtime/cgo.Handle
	// pattern here: cookie is never dereferenced as a real pointer, only round-tripped opaquely.
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

//export ox_stream_cancel_fn
func ox_stream_cancel_fn(cookie unsafe.Pointer) {
	if inst, ok := streamInstanceFor(cookie); ok {
		inst.Cancel()
	}
}
