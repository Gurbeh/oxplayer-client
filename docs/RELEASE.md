# Release guide (nightly · prerelease · release)

## Version bump (before any release)

**File:** `pubspec.yaml`

```yaml
version: M.m.p+1
```

- Change `M.m.p` (e.g. `1.0.1` → `1.0.2`). This is the user-visible version everywhere.
- Keep `+1` (or any small integer). Android `versionCode` is **not** taken from `+N`; it is computed in `android/app/build.gradle` as `major*100000 + minor*1000 + patch`. Minimum allowed: `100001`.

**Optional — Play Store “What’s new” text**

**File:** `fastlane/metadata/android/en-US/changelogs/{M.m.p}.txt`

Create or edit that file with the short changelog string (one line is fine).  
If you skip this, **Prepare Release** will overwrite it with a link to the GitHub release.

```bash
git add pubspec.yaml fastlane/metadata/android/en-US/changelogs/
git commit -m "chore: bump version to M.m.p"
git push origin main
```

CI skips the **nightly** build for commits that match `chore: bump version…`, `chore: prepare release…`, or `Release M.m.p:…` — otherwise release would build twice (main nightly + tag `v*`). Do **not** put `[skip ci]` on those commits: GitHub would also skip the tag-triggered release workflow.

---

## Nightly

Nightly = push to `main` (automatic) or manual dispatch. GitHub prerelease tag: `nightly`.

### Option A — automatic (after merge to `main`)

No extra edits beyond your normal commit. Push to `main`:

```bash
git push origin main
```

### Option B — manual re-run without a new commit

```bash
gh workflow run "Build OXPlayer" \
  --repo Gurbeh/oxplayer-client \
  --ref main \
  -f build_type=nightly
```

### Optional — redeploy web to GitHub Pages only

```bash
gh workflow run "Deploy website (GitHub Pages)" \
  --repo Gurbeh/oxplayer-client \
  --ref main
```

### Check result

```bash
gh run list --repo Gurbeh/oxplayer-client --workflow="Build OXPlayer" --limit 3
gh release view nightly --repo Gurbeh/oxplayer-client
```

---

## Prerelease

In this repo, **nightly and prerelease are the same pipeline**. The GitHub release is always named `OXPlayer nightly — {version}-nightly`, tag `nightly`, marked **Pre-release**.

Use the **Nightly** steps above.  
Do **not** create a `v*` tag for a prerelease.

**ghcr.io Docker** (`oxplayer`, `oxplayer-rootless`) is published on both **nightly** and **release** builds after **Create Release** succeeds.

---

## Release (stable)

**Preferred (no agent):** from sibling `oxplayer-be`:

```bash
pnpm release:all -y "One-line summary"
# client-only: bash scripts/release-client.sh -y "…"
```

Bumps version, writes Play changelog, tags `v{M.m.p}`, pushes. Local verify skipped; **Build OXPlayer** CI is the gate.

Stable release = semver tag `v{M.m.p}` + draft GitHub release + Play production path (promote draft in Console after upload).

### 1. Bump version (see top) — or use script above

Confirm the tag does not exist yet:

```bash
git fetch origin --tags
git tag -l "v*"
grep '^version:' pubspec.yaml
```

### 2. Prepare tag and fastlane changelog

```bash
gh workflow run "Prepare Release" --repo Gurbeh/oxplayer-client
```

Wait until it finishes:

```bash
gh run list --repo Gurbeh/oxplayer-client --workflow="Prepare Release" --limit 1
```

Pull the changelog commit if **Prepare Release** pushed one:

```bash
git pull origin main
```

> **Prepare Release** pushes the tag with `GITHUB_TOKEN`, which does **not** start **Build OXPlayer**. You must dispatch the release build yourself (step 3).
> Prefer `release-client.sh` / `pnpm release:all` — those push the tag with your credentials so the release build starts automatically.

### 3. Build release artifacts

Replace `vM.m.p` with your tag (e.g. `v1.0.2`):

```bash
gh workflow run "Build OXPlayer" \
  --repo Gurbeh/oxplayer-client \
  --ref vM.m.p \
  -f build_type=release
```

Watch the run:

```bash
gh run watch --repo Gurbeh/oxplayer-client
```

### 4. Publish GitHub draft

When **Create Release** is green, open the draft and publish it:

```bash
gh release list --repo Gurbeh/oxplayer-client --limit 5
```

In the browser: **Releases → OXPlayer {M.m.p} (Draft) → Publish release**

Or with CLI (replace tag):

```bash
gh release edit vM.m.p --repo Gurbeh/oxplayer-client --draft=false
```

### 5. Play Console

- **Nightly** uploads to **internal** track automatically.
- **Release** upload also targets **internal** in CI; promote to production in Play Console when ready.
- **`Version code … has already been used`** — expected when nightly already uploaded the same `M.m.p`. Android `versionCode` is fixed per semver (`major*100000 + minor*1000 + patch`). No action needed; promote the existing internal build in Play Console. CI treats this as non-fatal (`continue-on-error`).
- To ship a **new** Play build, bump `M.m.p` in `pubspec.yaml` first (e.g. `1.0.1` → `1.0.2` → versionCode `100002`).

### 6. Android in-app update prompt

Play installs use Google Play's in-app update API directly (same as Windows uses GitHub Releases).

`GET /ox/client/android-update` returns the latest **GitHub release** tag (`Gurbeh/oxplayer-client`, cached ~15m) for ops + as a fallback only when the Play API call itself fails. No Infisical bump needed after each release.

```bash
curl -s https://api.oxplayer.app/ox/client/android-update
# expect {"version":"M.m.p"} matching latest GitHub release
```

Optional emergency override only: set `OXPLAYER_ANDROID_MARKET_VERSION` in Infisical `/core/api` when GitHub is unreachable — leave unset in normal ops.
### 7. Web (Hetzner static) — `oxplayer.ir` / `web.oxplayer.app`

On **release** builds (`build_type=release`), **Deploy Web · Hetzner** dispatches `oxplayer-be` → SSH → `/srv/oxplayer-web`. This is **not** GitHub Pages or ghcr.io Docker — those update separately.

**One-time setup** (required — release CI **fails** if missing):

Fine-grained PAT on account with access to `Aryan-mor/oxplayer-be`:

- Repository access: `Aryan-mor/oxplayer-be`
- Permissions: **Contents** read, **Actions** read + write (workflow dispatch)

Store as **`OXPLAYER_BE_DISPATCH_TOKEN`** in **either**:

1. **GitHub secret** on `Gurbeh/oxplayer-client` (quick):

```bash
gh secret set OXPLAYER_BE_DISPATCH_TOKEN --repo Gurbeh/oxplayer-client
# paste PAT when prompted
```

2. **Infisical** `/core/client-ci` (preferred with other CI secrets):

```bash
# oxplayer-be repo — admin machine identity
export OXPLAYER_BE_DISPATCH_TOKEN='<same PAT>'
pnpm infisical:bootstrap-client-ci
```

`scripts/release-client.sh` refuses to push a release tag until the GitHub secret exists (local guard). CI loads Infisical first, then falls back to the GitHub secret.

**Manual redeploy** (any semver already built):

```bash
gh workflow run "Deploy · Web (Hetzner static)" \
  --repo Aryan-mor/oxplayer-be \
  -f version=M.m.p
```

Verify:

```bash
gh run list --repo Aryan-mor/oxplayer-be --workflow="Deploy · Web (Hetzner static)" --limit 3
curl -fsSI https://web.oxplayer.app/main.dart.js | grep -i last-modified
```

---

## Quick reference

| Goal | Edit | Commands |
|------|------|----------|
| Nightly build | `pubspec.yaml` (only if you want a new version name) | `git push origin main` **or** `gh workflow run "Build OXPlayer" … -f build_type=nightly` |
| GitHub Pages web | — | auto on `main` push, or `gh workflow run "Deploy website (GitHub Pages)" …` |
| ghcr.io Docker web | — | auto on nightly/release **Build OXPlayer** (after **Create Release**) |
| Prerelease assets | same as nightly | same as nightly |
| Stable release | `pubspec.yaml` + optional `fastlane/.../changelogs/{M.m.p}.txt` | `Prepare Release` → `Build OXPlayer` on `vM.m.p` with `build_type=release` → publish draft |
| Hetzner web (`oxplayer.ir`) | `OXPLAYER_BE_DISPATCH_TOKEN` once | auto on release **Build OXPlayer** → **Deploy Web · Hetzner** |

## Local Android sanity check (optional)

```bash
flutter build appbundle --release --flavor production
```

Requires `android/app/keystore.jks` and `android/key.properties` locally.
