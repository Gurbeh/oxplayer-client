//go:build android

// jni_bridge.go is the genuinely Android-specific piece of this artifact: it reaches back into
// the JVM, via JNI, to the existing gomobile-bound PlaybackSession (go/oxtelegram/mobile) that
// Kotlin already created through the normal auth/resolve/download-open flow — because that
// session's underlying gotd/td connection lives in a *different* compiled Go runtime (the
// gomobile .so) than this one, and its session credentials are Android-Keystore-encrypted
// (readable only via the JVM's EncryptedSharedPreferences API), this .so cannot open or drive a
// download connection on its own the way cshared/main.go does for Windows.
//
// Scope of the JNI crossing (this is the load-bearing design decision, not an implementation
// detail): once per session open (localPath/size), and once per *real cache miss* during a read
// (ensureAvailable) — never once per mpv read_fn call. This exactly mirrors the reactive
// "only round-trip when about to read past the known-available window" guard already proven in
// TdlibHttpBridgeServer.kt/DownloadByteSource for the HTTP bridge path; the class of bug that
// motivated this whole migration (HTTP reconnect storms on rapid seek) is about round-tripping on
// every byte range, not about occasionally crossing into the JVM when data genuinely isn't ready
// yet.
//
// Kotlin side: app/oxplayer/tdlibbridge/player/OxTelegramStreamBridge.kt — a registry keyed by
// the same int id embedded in the "gotdstream://{id}" uri, holding the live PlaybackSession.
package main

/*
#include <jni.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static JavaVM *g_vm = NULL;
static jclass g_bridgeClass = NULL;
static jmethodID g_openSessionAsyncMethod = NULL;
static jmethodID g_ensureAvailableAsyncMethod = NULL;
static jmethodID g_cancelCurrentReadMethod = NULL;

// One of these is malloc'd per in-flight ensureAvailable call; its own pointer (cast to jlong) is
// the "requestId" Kotlin echoes back in nativeOnEnsureAvailableComplete — no separate lookup
// table needed. See ox_jni_ensure_available's doc for why this hop through a condition variable
// exists at all instead of a direct blocking JNI call.
//
// Ownership/cleanup: whichever side — the native waiter timing out, or this completion callback
// arriving — touches `abandoned`/`done` *second* is the one that frees req. This avoids a
// use-after-free if the native-side safety-net timeout fires (freeing req) shortly before a
// genuinely-late completion callback also tries to touch it: the callback checks `abandoned`
// under the same mutex and frees instead of signaling in that case.
typedef struct {
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	int done;
	int success;
	int abandoned;
} ox_ensure_request;

static void ox_ensure_request_free(ox_ensure_request *req) {
	pthread_mutex_destroy(&req->mutex);
	pthread_cond_destroy(&req->cond);
	free(req);
}

// Implements OxTelegramStreamBridge.nativeOnEnsureAvailableComplete (Kotlin `external fun`,
// registered below via RegisterNatives). Always called from a Kotlin coroutine thread, after
// PlaybackSession.ensureAvailable has already fully returned on that thread — never nested with
// it, which is the entire point of routing through here instead of a direct blocking call.
static void JNICALL ox_native_on_ensure_available_complete(JNIEnv *env, jclass clazz,
                                                            jlong requestId, jboolean success) {
	ox_ensure_request *req = (ox_ensure_request *)(intptr_t)requestId;
	if (!req) return;
	pthread_mutex_lock(&req->mutex);
	if (req->abandoned) {
		// The native waiter already gave up (safety-net timeout) and left cleanup to whoever
		// touched req second — that's us.
		pthread_mutex_unlock(&req->mutex);
		ox_ensure_request_free(req);
		return;
	}
	req->done = 1;
	req->success = success == JNI_TRUE ? 1 : 0;
	pthread_cond_signal(&req->cond);
	pthread_mutex_unlock(&req->mutex);
}

// Same shape/ownership rules as ox_ensure_request (see its doc) — for openSessionAsync's result,
// which additionally carries a heap-allocated copy of the resolved local cache file path.
typedef struct {
	pthread_mutex_t mutex;
	pthread_cond_t cond;
	int done;
	int success;
	int abandoned;
	char *localPath; // malloc'd by the completion callback; ownership transfers to whoever frees the struct
	long long size;
} ox_open_request;

static void ox_open_request_free(ox_open_request *req) {
	pthread_mutex_destroy(&req->mutex);
	pthread_cond_destroy(&req->cond);
	free(req->localPath);
	free(req);
}

// Implements OxTelegramStreamBridge.nativeOnOpenSessionComplete — same pattern as
// ox_native_on_ensure_available_complete, see its doc.
static void JNICALL ox_native_on_open_session_complete(JNIEnv *env, jclass clazz, jlong requestId,
                                                        jboolean success, jstring localPath, jlong size) {
	ox_open_request *req = (ox_open_request *)(intptr_t)requestId;
	if (!req) return;

	char *pathCopy = NULL;
	if (success && localPath != NULL) {
		const char *chars = (*env)->GetStringUTFChars(env, localPath, NULL);
		if (chars != NULL) {
			pathCopy = strdup(chars);
			(*env)->ReleaseStringUTFChars(env, localPath, chars);
		}
	}

	pthread_mutex_lock(&req->mutex);
	if (req->abandoned) {
		pthread_mutex_unlock(&req->mutex);
		free(pathCopy);
		ox_open_request_free(req);
		return;
	}
	req->done = 1;
	req->success = (success == JNI_TRUE && pathCopy != NULL) ? 1 : 0;
	req->localPath = pathCopy;
	req->size = size;
	pthread_cond_signal(&req->cond);
	pthread_mutex_unlock(&req->mutex);
}

// JNI_OnLoad runs on the thread that calls System.loadLibrary() from Kotlin — the *only* thread
// guaranteed to resolve FindClass against the app's own classloader rather than the bootstrap
// classloader (a well-known Android JNI pitfall: FindClass from a later-attached native thread,
// e.g. mpv's internal demuxer thread, cannot see app classes at all). Caching the class as a
// global ref + method IDs here, once, is the standard fix — every other function below only ever
// uses these cached values, never calls FindClass again.
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
	JNIEnv *env;
	if ((*vm)->GetEnv(vm, (void **)&env, JNI_VERSION_1_6) != JNI_OK) {
		return -1;
	}
	g_vm = vm;

	jclass localClass = (*env)->FindClass(env, "app/oxplayer/tdlibbridge/player/OxTelegramStreamBridge");
	if (localClass == NULL) {
		return -1;
	}
	g_bridgeClass = (jclass)(*env)->NewGlobalRef(env, localClass);
	(*env)->DeleteLocalRef(env, localClass);

	g_openSessionAsyncMethod = (*env)->GetStaticMethodID(env, g_bridgeClass, "openSessionAsync", "(IJ)V");
	g_ensureAvailableAsyncMethod = (*env)->GetStaticMethodID(env, g_bridgeClass, "ensureAvailableAsync", "(IJJJ)V");
	g_cancelCurrentReadMethod = (*env)->GetStaticMethodID(env, g_bridgeClass, "cancelCurrentRead", "(I)V");

	if (g_openSessionAsyncMethod == NULL ||
		g_ensureAvailableAsyncMethod == NULL || g_cancelCurrentReadMethod == NULL) {
		return -1;
	}

	JNINativeMethod natives[] = {
		{"nativeOnEnsureAvailableComplete", "(JZ)V", (void *)ox_native_on_ensure_available_complete},
		{"nativeOnOpenSessionComplete", "(JZLjava/lang/String;J)V", (void *)ox_native_on_open_session_complete},
	};
	if ((*env)->RegisterNatives(env, g_bridgeClass, natives, 2) != 0) {
		return -1;
	}
	return JNI_VERSION_1_6;
}

// ox_attach/ox_detach: read_fn/seek_fn/cancel_fn run on mpv's own native threads, never attached
// to the JVM by default — AttachCurrentThread is required before any JNI call, and must be
// paired with DetachCurrentThread only if *this* call performed the attach (a thread already
// attached, e.g. by an earlier call reusing the same underlying OS thread, must not be detached
// out from under whatever attached it).
static JNIEnv *ox_attach(int *didAttach) {
	JNIEnv *env = NULL;
	*didAttach = 0;
	if (g_vm == NULL) return NULL;
	jint rs = (*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6);
	if (rs == JNI_EDETACHED) {
		if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != 0) return NULL;
		*didAttach = 1;
	} else if (rs != JNI_OK) {
		return NULL;
	}
	return env;
}

static void ox_detach(int didAttach) {
	if (didAttach && g_vm != NULL) {
		(*g_vm)->DetachCurrentThread(g_vm);
	}
}

// Blocks the calling native thread until OxTelegramStreamBridge.openSessionAsync's coroutine
// (running on its own thread — never PlaybackSession called directly here, see file/class doc)
// resolves the session's local cache file path + size. On success, *outPath is a malloc'd,
// NUL-terminated UTF-8 string the caller must free(); *outSize is the file size. Returns 0 on
// failure/timeout (in which case *outPath is left untouched — caller must not free it), 1 on
// success.
static int ox_jni_open_session(int id, char **outPath, long long *outSize) {
	ox_open_request *req = malloc(sizeof(ox_open_request));
	if (!req) return 0;
	pthread_mutex_init(&req->mutex, NULL);
	pthread_cond_init(&req->cond, NULL);
	req->done = 0;
	req->success = 0;
	req->abandoned = 0;
	req->localPath = NULL;
	req->size = -1;

	int didAttach;
	JNIEnv *env = ox_attach(&didAttach);
	if (env == NULL || g_bridgeClass == NULL) {
		ox_open_request_free(req);
		return 0;
	}
	(*env)->CallStaticVoidMethod(env, g_bridgeClass, g_openSessionAsyncMethod, (jint)id, (jlong)(intptr_t)req);
	int dispatchFailed = (*env)->ExceptionCheck(env);
	if (dispatchFailed) {
		(*env)->ExceptionClear(env);
	}
	ox_detach(didAttach);

	if (dispatchFailed) {
		ox_open_request_free(req);
		return 0;
	}

	// Session open only needs one gomobile round-trip (no big download to wait for), so this can
	// be much tighter than ensureAvailable's timeout — comfortably above ordinary JNI/coroutine
	// dispatch latency.
	struct timespec deadline;
	clock_gettime(CLOCK_REALTIME, &deadline);
	deadline.tv_sec += 30;

	pthread_mutex_lock(&req->mutex);
	while (!req->done) {
		if (pthread_cond_timedwait(&req->cond, &req->mutex, &deadline) != 0) {
			break;
		}
	}
	if (req->done) {
		int result = req->success;
		if (result) {
			*outPath = req->localPath;
			*outSize = req->size;
			req->localPath = NULL; // ownership transferred to caller
		}
		pthread_mutex_unlock(&req->mutex);
		ox_open_request_free(req);
		return result;
	}
	req->abandoned = 1;
	pthread_mutex_unlock(&req->mutex);
	return 0;
}

// Blocks the calling native thread until [offset, offset+length) is downloaded, WITHOUT calling
// PlaybackSession.ensureAvailable directly on this thread (see file/class doc: this thread is
// already inside liboxtelegramstream.so's own Go runtime's cgo stack, and the gomobile Go runtime
// backing PlaybackSession cannot be nested inside it on the same OS thread without crashing).
// Instead: kick off OxTelegramStreamBridge.ensureAvailableAsync (a fire-and-forget JNI call that
// only launches a Kotlin coroutine — no Go code runs synchronously inside it), detach from the
// JVM, and block on a plain pthread condition variable until that coroutine (running on its own,
// never-adopted-by-either-Go-runtime thread) reports completion via
// ox_native_on_ensure_available_complete. Returns 0 on failure/timeout, 1 on success.
static int ox_jni_ensure_available(int id, long long offset, long long length) {
	ox_ensure_request *req = malloc(sizeof(ox_ensure_request));
	if (!req) return 0;
	pthread_mutex_init(&req->mutex, NULL);
	pthread_cond_init(&req->cond, NULL);
	req->done = 0;
	req->success = 0;
	req->abandoned = 0;

	int didAttach;
	JNIEnv *env = ox_attach(&didAttach);
	if (env == NULL || g_bridgeClass == NULL) {
		ox_ensure_request_free(req);
		return 0;
	}
	(*env)->CallStaticVoidMethod(env, g_bridgeClass, g_ensureAvailableAsyncMethod,
		(jint)id, (jlong)(intptr_t)req, (jlong)offset, (jlong)length);
	int dispatchFailed = (*env)->ExceptionCheck(env);
	if (dispatchFailed) {
		(*env)->ExceptionClear(env);
	}
	ox_detach(didAttach); // don't hold the JVM attachment while blocked below

	if (dispatchFailed) {
		// ensureAvailableAsync itself never ran (or threw before dispatching), so no completion
		// callback will ever arrive for this req — safe to free immediately, nobody else has it.
		ox_ensure_request_free(req);
		return 0;
	}

	// Safety-net cap comfortably above Kotlin's own PlaybackSession.EnsureAvailable timeout (2
	// minutes, mobile/bind.go) plus Go's own StreamInstance timeout (2 minutes,
	// stream_instance.go) — this thread must not block forever if the completion callback is
	// ever genuinely lost.
	struct timespec deadline;
	clock_gettime(CLOCK_REALTIME, &deadline);
	deadline.tv_sec += 150;

	pthread_mutex_lock(&req->mutex);
	while (!req->done) {
		if (pthread_cond_timedwait(&req->cond, &req->mutex, &deadline) != 0) {
			break; // timed out or errored
		}
	}
	if (req->done) {
		int result = req->success;
		pthread_mutex_unlock(&req->mutex);
		ox_ensure_request_free(req);
		return result;
	}
	// Timed out: mark abandoned and leave freeing to the completion callback, in case it's just
	// running very late rather than truly lost (see struct doc for why this is safe).
	req->abandoned = 1;
	pthread_mutex_unlock(&req->mutex);
	return 0;
}

static void ox_jni_cancel_current_read(int id) {
	int didAttach;
	JNIEnv *env = ox_attach(&didAttach);
	if (env == NULL || g_bridgeClass == NULL) return;
	(*env)->CallStaticVoidMethod(env, g_bridgeClass, g_cancelCurrentReadMethod, (jint)id);
	if ((*env)->ExceptionCheck(env)) {
		(*env)->ExceptionClear(env);
	}
	ox_detach(didAttach);
}
*/
import "C"

import (
	"context"
	"fmt"
	"unsafe"
)

// jniByteSource implements oxtelegram.ByteSource by calling back into the JVM's already-open
// gomobile PlaybackSession via JNI (see file doc for exactly when: open + real cache misses
// only). Wrapped by the same oxtelegram.StreamInstance Windows uses — nothing about the
// read/seek/size/cancel logic differs per platform, only how ByteSource reaches real bytes does.
type jniByteSource struct {
	id        int
	size      int64
	localPath string
}

func newJNIByteSource(id int) (*jniByteSource, error) {
	var cPath *C.char
	var cSize C.longlong
	if C.ox_jni_open_session(C.int(id), &cPath, &cSize) == 0 {
		return nil, fmt.Errorf("jni: openSession failed for id %d (not registered, JNI_OnLoad's class cache failed, or timed out)", id)
	}
	defer C.free(unsafe.Pointer(cPath))
	path := C.GoString(cPath)
	if path == "" {
		return nil, fmt.Errorf("jni: empty localPath for id %d", id)
	}
	return &jniByteSource{id: id, size: int64(cSize), localPath: path}, nil
}

func (s *jniByteSource) Size() int64       { return s.size }
func (s *jniByteSource) LocalPath() string { return s.localPath }

// AvailableFrom/AvailableUpTo/IsComplete are part of the ByteSource interface but not called by
// StreamInstance (only Size/LocalPath/EnsureAvailable are) — stubbed rather than adding three
// more JNI method lookups for values nothing currently reads.
func (s *jniByteSource) AvailableFrom() int64 { return 0 }
func (s *jniByteSource) AvailableUpTo() int64 { return 0 }
func (s *jniByteSource) IsComplete() bool     { return false }

// EnsureAvailable blocks in Kotlin's PlaybackSession.ensureAvailable (via JNI) until
// [offset, offset+length) is downloaded — only reached by StreamInstance.Read on an actual cache
// miss. The blocking JNI call itself can't observe ctx.Done(), so cancellation is threaded back
// as a second JNI call (cancelCurrentRead) that PlaybackSession already supports being
// interrupted by internally (see mobile/bind.go's own cancels list).
func (s *jniByteSource) EnsureAvailable(ctx context.Context, offset, length int64) error {
	done := make(chan bool, 1)
	go func() {
		done <- C.ox_jni_ensure_available(C.int(s.id), C.longlong(offset), C.longlong(length)) != 0
	}()
	select {
	case ok := <-done:
		if !ok {
			return fmt.Errorf("jni: ensureAvailable failed id=%d offset=%d length=%d", s.id, offset, length)
		}
		return nil
	case <-ctx.Done():
		C.ox_jni_cancel_current_read(C.int(s.id))
		<-done // wait for the JNI call to actually return before unwinding this stack frame
		return ctx.Err()
	}
}

func (s *jniByteSource) CancelCurrentRead() {
	C.ox_jni_cancel_current_read(C.int(s.id))
}
