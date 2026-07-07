# OXPlayer Client

Flutter client based on [Fladder](https://github.com/DonutWare/fladder), focused on your **Telegram media library** via the OXPlayer API.

## OX build flag

OX-specific hooks and **Telegram-first login** run by default.

Use vanilla Fladder-style startup when you need upstream behavior:

```bash
flutter run --dart-define=OXPLAYER=false
```

Implementation lives in [`lib/oxplayer/`](lib/oxplayer/README.md).

## Upstream (Fladder)

First-time Git setup and how we port stable Fladder releases: [`docs/UPSTREAM_SYNC.md`](docs/UPSTREAM_SYNC.md).

Quick start after clone:

```bash
git remote add upstream https://github.com/DonutWare/fladder.git   # if missing
git fetch upstream
git remote set-head upstream main   # local; use upstream/main for ports
```

## API

Point the app at your `oxplayer` API base URL (set in `assets/env/default.env` or `--dart-define`) under `lib/oxplayer/`.

## Sentry (optional)

Set `SENTRY_DSN` in `assets/env/default.env`, `dart_defines.*.json`, or `--dart-define` (same variable names as the `oxplayer` API). When the DSN is empty, the SDK is not loaded. Implementation: `lib/oxplayer/oxplayer_sentry.dart`.

Release CI uploads Dart debug symbols and ProGuard mappings via `sentry_dart_plugin` using `SENTRY_AUTH_TOKEN` from Infisical `/core/client-ci` (org/project/url are in `pubspec.yaml`). Local release upload after a build with `--split-debug-info=build/debug-info`:

```bash
export SENTRY_AUTH_TOKEN=... SENTRY_URL=https://de.sentry.io
export SENTRY_RELEASE=oxplayer-client@$(grep '^version:' pubspec.yaml | cut -d' ' -f2 | tr -d ' ')
export SENTRY_DIST=<same build number as flutter --build-number>
dart run sentry_dart_plugin
```
