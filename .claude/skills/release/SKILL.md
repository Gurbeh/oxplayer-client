---
name: release
description: >
  OXPlayer Android release workflow (Fladder-aligned CI). Covers versioning rules,
  the prepare-release → tag → build → Play-upload pipeline, and the pre-release
  checklist. Use when the user asks to cut a release, bump the version, tag a
  release, publish to Play Console, or debug a Play Console "can't upgrade
  existing users" / versionCode error. Mirrors .cursor/rules/oxplayer-release.mdc —
  keep both in sync if either changes.
---

Same model as upstream [DonutWare/fladder](https://github.com/DonutWare/fladder) Android pipeline.

## Versioning

| Field | Source | Notes |
|-------|--------|-------|
| **versionName** | `pubspec.yaml` before `+` | e.g. `0.0.4` |
| **versionCode (CI builds)** | `10000 + github.run_number` | Must exceed all legacy Play uploads (split APKs use `base*1000+abi`) |
| **Git tag** | `v{versionName}` | e.g. `v0.0.4` |

Local/dev builds may still use pubspec `+N`; CI always passes `--build-number=${{ github.run_number }}`.

## Pre-release checklist

```bash
git fetch origin --tags
git log origin/main -1 --oneline
git tag -l 'v*' | tail -5
grep '^version:' pubspec.yaml
ls fastlane/metadata/android/en-US/changelogs/
```

Before tagging:

1. Bump **version name** in `pubspec.yaml` (e.g. `0.0.3+8` → `0.0.4+8` — the `+` suffix is for local builds only).
2. Confirm `v{versionName}` tag does **not** exist.
3. Commit and push to `main`.

## Release steps

1. **Prepare Release** (workflow_dispatch on `main`) → fastlane `changelogs/{versionName}.txt` + tag `v*`
2. Tag push → **Build OXPlayer** (`build_type=release`) → signed APK/AAB + GitHub draft release
3. **Play upload** (if `SERVICE_ACCOUNT_JSON` set): release → `production` / `draft`; nightly → `internal` / `completed`
4. Publish GitHub draft when green.

## Triggers (Android)

| Event | build_type | GitHub Release | Play upload |
|-------|------------|----------------|-------------|
| Tag `v*` | release | draft | production (draft) |
| Schedule / manual nightly | nightly | prerelease `nightly` | internal (completed) |
| PR | development | no | no |
| Push to `main` | nightly | prerelease `nightly` | internal (completed) |

## OX-only additions (keep when syncing from Fladder)

- `./.github/actions/oxplayer-flutter-env`
- Sentry symbol upload (`continue-on-error: true`)
- Admin Telegram notify after GitHub release
- Package `app.oxplayer`

## Never do

- Use pubspec `+N` or raw `github.run_number` as CI `--build-number` (breaks upgrade path vs legacy split APKs on Play).
- Upload split APKs from GitHub Releases to Play Console — **AAB only**.
- Re-tag an existing `v*` without bumping version name in pubspec.

## Play Console: "can't upgrade existing users"

Usually **versionCode too low** vs artifacts already on a track (e.g. split APKs `1007/2007/3007` while AAB used `35`).

1. **Release overview** → note highest **Version code** on internal/production.
2. Ensure next CI build uses `10000 + run_number` (must be **greater** than that max).
3. In the draft release, keep **only the new AAB** — remove any old APK rows.
4. Discard the broken release and let CI upload a fresh AAB, or promote after a green run.
