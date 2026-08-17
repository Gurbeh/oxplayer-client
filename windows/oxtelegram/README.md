# oxtelegram.dll (Windows)

gotd-only Telegram host for OXPlayer Windows (`c-shared` from `go/oxtelegram/cshared`).
No TDLib. Provides auth, progressive download, and loopback HTTP Range bridge for libmpv.

Rebuild whenever `go/oxtelegram/cshared` exports change. A stale committed DLL
ships with `flutter build windows` and fails at runtime (`Failed to lookup symbol`).
CI `build-windows` rebuilds this DLL before packaging.

## Rebuild

Requires Go with CGO and MinGW-w64 `gcc` on PATH.

```powershell
cd go\oxtelegram
$env:CGO_ENABLED = "1"
go build -buildmode=c-shared -o ..\..\windows\oxtelegram\oxtelegram.dll .\cshared
```

Flutter install step copies `oxtelegram.dll` next to the runner executable.

## Run (dev)

Android gets `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` via `pnpm run dev:android` → `--dart-define-from-file`.
Bare `flutter run -d windows` does **not** — use:

```powershell
.\windows\oxtelegram\run-windows.ps1
```

or:

```powershell
$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-21.0.12.8-hotspot"
$env:CMAKE_GENERATOR = "Visual Studio 17 2022"
flutter run -d windows --dart-define-from-file=dart_defines.dev.json
```

If `dart_defines.dev.json` is missing, from `oxplayer-be`: `pnpm run sync:client-env`.

## Android AAR (shared Go core)
```powershell
cd go\oxtelegram
gomobile bind -target=android -androidapi 24 -o ..\..\android\ox_tdlib_bridge\libs\oxtelegram.aar .\mobile
```

HTTP bridge lives in Go (`http_bridge.go`); Android may still use the Kotlin loopback server
backed by the same `PlaybackSession` until the AAR is regenerated with `NewHttpBridgeServer`.
