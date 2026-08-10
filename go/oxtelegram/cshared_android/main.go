//go:build android

// Package main builds liboxtelegramstream_<abi>.so (cgo c-shared) for Android — the stream_cb
// hot-path counterpart to the gomobile-bound liboxtelegram.aar (go/oxtelegram/mobile), NOT a
// replacement for it. Auth/session/resolve/download-session-open stay on the existing gomobile
// path (JVM-integrated, proven, and the only thing that CAN read the Keystore-backed session —
// see stream_bridge.go's doc for why). This artifact exists solely so mpv's native demuxer
// thread can call read/seek/size/cancel directly, without crossing into the JVM on the hot path.
//
//	go build -buildmode=c-shared -o liboxtelegramstream.so ./cshared_android
//
// STATUS: builds and exports correctly for all three vendored ABIs (arm64-v8a, armeabi-v7a,
// x86_64) via the NDK toolchain. The JNI handoff to Kotlin's OxTelegramStreamBridge
// (jni_bridge.go) is implemented but UNTESTED against a live JVM/Android runtime — cross-compiled
// unit testing cannot exercise a real JNI_OnLoad/FindClass/AttachCurrentThread round-trip, only a
// real device can. Treat as unproven until validated on-device (see joint device-testing phase).
package main

import "C"

func main() {}
