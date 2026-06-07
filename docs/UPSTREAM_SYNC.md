# Upstream Fladder — setup & sync

This repo is a **Fladder-based** client with OXPlayer product code in `lib/oxplayer/`. Almost everything else under `lib/` is upstream Fladder behavior.

Upstream project: [DonutWare/fladder](https://github.com/DonutWare/fladder)

Optional monorepo snapshot for file diffs: `../refs/Fladder`

---

## Mental model

```
Fladder (upstream/main)  ──manual port──►  oxplayer-client (origin/main)
                                              └── lib/oxplayer/  (OX-only)
```

- **Git histories are unrelated** — `git merge upstream/main` usually fails with *unrelated histories*.
- **Do not edit Fladder code** to fix Jellyfin/API bugs; fix **`oxplayer-be`** instead (see `.cursor/rules/fladder-no-edit-trust-jellyfin.mdc`).
- **OX-only logic** stays in `lib/oxplayer/` and behind `OxplayerConfig.isEnabled`.

---

## One-time setup (new developer / new machine)

After cloning **oxplayer-client**:

```bash
# 1. Confirm remotes
git remote -v
# origin   → your fork / team repo (push target)
# upstream → https://github.com/DonutWare/fladder.git (read-only reference)

# 2. Add upstream if missing
git remote add upstream https://github.com/DonutWare/fladder.git

# 3. Fetch all upstream branches
git fetch upstream

# 4. Pin local upstream default to main (stable release branch)
git remote set-head upstream main
```

Verify:

```bash
git symbolic-ref refs/remotes/upstream/HEAD
# → refs/remotes/upstream/main
```

**No push is required** after step 4. `git remote set-head` is a **local** setting (stored under `.git/`). Each developer runs the same commands on their machine.

GitHub’s default branch for Fladder is still `develop`; we intentionally track **`upstream/main`** for ports because it matches released/stable Fladder. `upstream/develop` remains available after `git fetch upstream` if you need to inspect unreleased work — do not switch the default unless the team decides to.

---

## Remotes at a glance

| Remote | URL (typical) | Purpose |
|--------|----------------|---------|
| `origin` | `https://github.com/Gurbeh/oxplayer-client.git` | Push OXPlayer work here |
| `upstream` | `https://github.com/DonutWare/fladder.git` | Read-only; compare & port Fladder fixes |

Wrong `origin` URL? `git remote set-url origin <new-url>`

---

## Sync workflow (porting upstream changes)

Prefer **commit-by-commit porting** over blind merge.

```bash
git fetch upstream
git log --oneline -30 upstream/main          # see new stable commits
git show <commit> --stat                       # scope
git show <commit> -- lib/path/to/file.dart     # patch to apply
```

For each commit (oldest → newest when order matters):

1. Apply equivalent edits in this tree.
2. **Keep** `lib/oxplayer/` and OX hook sites in `main.dart` / bootstrap — merge behavior, do not overwrite.
3. Skip packaging-only changes (fastlane, flatpak, Weblate-only) unless explicitly requested.
4. After `lib/l10n/*.arb` changes: `flutter gen-l10n` (`lib/l10n/generated` is gitignored).
5. Verify: `dart analyze` or `flutter analyze` on touched files.

Agent workflow for Cursor: `.cursor/rules/fladder-upstream-sync.mdc`

---

## What not to do

| Avoid | Why |
|-------|-----|
| `git merge upstream/main` expecting a clean merge | Unrelated histories; high conflict risk |
| Replacing Fladder files wholesale from upstream | Wipes OX hooks and custom login/sync paths |
| Porting from `develop` by default | Unstable; may pull unreleased refactors |
| Pushing to `upstream` | No write access; not needed |

---

## OX guard rule

OX-only code must stay behind `OxplayerConfig.isEnabled` (on by default; `--dart-define=OXPLAYER=false` for vanilla Fladder startup) and live in `lib/oxplayer/`. That keeps the conflict surface small when porting.

See also: [`lib/oxplayer/README.md`](../lib/oxplayer/README.md), `.cursor/rules/oxplayer-override-strategy.mdc`

---

## Reference tree

The workspace may keep `refs/Fladder` as a read-only checkout for side-by-side diffs. The shipping app is this `oxplayer-client` tree.
