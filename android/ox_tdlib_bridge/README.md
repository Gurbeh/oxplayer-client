# ox_tdlib_bridge

Thin Kotlin wrapper around **official TDLib** (`github.com/tdlib/td`) used for client-side
Telegram direct-play: the end user logs into their own Telegram account inside the app, and this
module resolves the public provider channel + downloads video bytes directly from Telegram,
feeding them to ExoPlayer. No server byte relay (`ox-stream`/FileStreamBot) is involved.

See `oxplayer-be/docs/mtproto-direct-play-plan.md` for the full architecture and why this uses
TDLib rather than a from-scratch MTProto implementation.

## Native TDLib artifact: vendored, built from official source

`src/main/java/org/drinkless/tdlib/{Client,TdApi}.java` and `src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/libtdjni.so`
are vendored directly (not a Maven/JitPack dependency — TDLib has no official one, and the two
credible-looking third-party prebuilts were rejected: `TGX-Android/tdlib` explicitly disclaims use
outside Telegram X, and community Maven/JitPack packages are unverified single-maintainer
artifacts — not something to trust silently for a component holding a real user's Telegram
session). Built instead via TDLib's own official Docker build:

```sh
git clone https://github.com/tdlib/td.git
cd td/example/android
DOCKER_BUILDKIT=1 docker build --output tdlib .
```

- Source commit: `022d60202e446ad1287b9fb68e687c8a0760788b` (2026-07-17, `tdlib/td` master)
- Build args used: defaults (`TDLIB_INTERFACE=Java`, `ANDROID_STL=c++_static`, NDK `23.2.8568313`,
  OpenSSL `1.1.1w`) — `c++_static` statically links the C++ runtime into `libtdjni.so`, so it
  doesn't need `libc++_shared.so` packaged alongside it (relevant since `app/build.gradle`
  `pickFirsts`s that file from other native plugins).
- `x86` (32-bit) output was dropped, matching `app/build.gradle`'s existing exclusion of
  `lib/x86/**`; `x86_64` was kept for emulator/dev use.

**To rebuild against a newer TDLib commit:** rerun the Docker build above (optionally with
`--build-arg COMMIT_HASH=<hash>`), then replace both `src/main/java/org/drinkless/tdlib/` and
`src/main/jniLibs/` with the new output's `tdlib/java/org/drinkless/tdlib/` and `tdlib/libs/*`.

**Verified compiling** (`./gradlew :ox_tdlib_bridge:compileDebugKotlin` and `:app:compileDevelopmentDebugKotlin`,
both `BUILD SUCCESSFUL`) against the vendored `TdApi.java`/`Client.java` above. One real signature
mismatch was caught and fixed in this pass: `Client.send` takes the *raw* `TdApi.Function` type,
which Kotlin requires as a star-projection (`TdApi.Function<*>`), not the bare class reference
originally written — see `TdlibClient.send`. Everything else (state names, method names, field
names guessed against TDLib's documented shape before this artifact existed) matched as written.

Not yet verified: this is a compile-time check only, not a runtime one — no emulator/device run,
no real Telegram auth flow, no actual file download. See the plan doc's outstanding items (RAM
profiling, E2E test) for what's still needed before this ships.

## Scope (deliberately narrow — see plan doc B.2)

Auth (phone+code+2FA, QR for TV), resolve the public provider channel + message, download file
bytes from an arbitrary offset (for seek), feed ExoPlayer via a custom `DataSource`. No chat list
sync, no message database, no contacts sync, no background keep-alive when idle — configured via
a minimal `TdApi.SetTdlibParameters` (see `TdlibSessionConfig.kt`) to keep the Android TV RAM
footprint down.

## Package layout

```
session/          TdlibSessionConfig (SetTdlibParameters), TdlibClient (lifecycle + coroutine bridge)
auth/             TdlibAuthController (phone/QR/2FA state machine over UpdateAuthorizationState)
media/            TdlibChannelResolver (SearchPublicChat + GetMessage), TdlibFileFetcher (DownloadFile)
player/           TelegramFileDataSource (media3 DataSource reading from TDLib's downloaded file)
```
