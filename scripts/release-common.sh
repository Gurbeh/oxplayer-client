#!/usr/bin/env bash
# Shared helpers for release-be.sh / release-client.sh
set -euo pipefail

release_root() {
  git rev-parse --show-toplevel
}

release_require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" &>/dev/null; then
      echo "error: required command not found: ${cmd}" >&2
      exit 1
    fi
  done
}

release_ensure_gh_on_path() {
  if command -v gh &>/dev/null; then
    return 0
  fi
  # Git Bash / WSL often lack WinGet PATH for Windows gh.exe.
  local candidate dir
  for candidate in \
    "/mnt/c/Program Files/GitHub CLI/gh.exe" \
    "/mnt/c/Program Files (x86)/GitHub CLI/gh.exe" \
    "/c/Program Files/GitHub CLI/gh.exe" \
    "/c/Program Files (x86)/GitHub CLI/gh.exe"; do
    if [[ -f "${candidate}" ]]; then
      dir="$(dirname "${candidate}")"
      PATH="${dir}:${PATH}"
      export PATH
      if command -v gh &>/dev/null; then
        return 0
      fi
      # WSL: Windows binaries need the .exe name unless wrapped.
      if command -v gh.exe &>/dev/null; then
        gh() { command gh.exe "$@"; }
        export -f gh
        return 0
      fi
    fi
  done
  return 1
}

release_require_gh_auth() {
  release_ensure_gh_on_path || true
  release_require_cmd git
  if ! command -v gh &>/dev/null; then
    echo "error: required command not found: gh" >&2
    echo "Install GitHub CLI, or on WSL install: sudo apt install gh" >&2
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    echo "error: GitHub CLI not authenticated." >&2
    echo "Run: gh auth login" >&2
    exit 1
  fi
  gh auth setup-git &>/dev/null || true
}

release_preflight() {
  local root branch behind

  root="$(release_root)"
  cd "${root}"

  echo "=== preflight ==="
  # --tags can fail when a remote tag (e.g. nightly) would clobber a local one.
  git fetch origin --tags || echo "warn: some remote tags rejected (continuing)"
  git fetch origin main

  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "${branch}" != "main" ]]; then
    echo "error: must be on main (currently: ${branch})" >&2
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree not clean:" >&2
    git status --short >&2
    exit 1
  fi

  behind="$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [[ "${behind}" -gt 0 ]]; then
    echo "error: local main is ${behind} commit(s) behind origin/main — pull first" >&2
    exit 1
  fi

  echo "origin/main: $(git log origin/main -1 --oneline)"
  echo "recent tags: $(git tag -l 'v*' | tail -5 | tr '\n' ' ')"
}

release_run_verify() {
  local root
  root="$(release_root)"
  # Default: skip local verify — CI is the gate (faster release push).
  if [[ "${RELEASE_SKIP_VERIFY:-1}" == "1" ]]; then
    echo "Skipping local verify-all (CI is the gate; pass --verify to run locally)"
    return 0
  fi
  if [[ -f "${root}/scripts/verify-all.sh" ]]; then
    bash "${root}/scripts/verify-all.sh"
  fi
}

release_confirm() {
  local summary version tag ans

  summary="$1"
  version="$2"
  tag="$3"

  echo ""
  echo "Release plan:"
  echo "  version: ${version}"
  echo "  tag:     ${tag}"
  echo "  summary: ${summary}"
  echo ""

  if [[ "${RELEASE_YES:-0}" == "1" ]]; then
    return 0
  fi

  read -r -p "Continue? [y/N] " ans
  if [[ ! "${ans}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
}

release_show_help() {
  local script_name="$1"
  cat <<EOF
Usage: ${script_name} [options] [summary]

Summary is prompted if omitted.

Options:
  --dry-run      Show plan only; no file edits
  -y, --yes      Skip confirmation prompt
  --no-push      Commit and tag locally only
  --skip-verify  Default: skip local verify-all / pre-push (CI is the gate)
  --verify       Run scripts/verify-all.sh locally before bump/push

Requires: gh auth login, clean main, up to date with origin/main
EOF
}

release_parse_args() {
  RELEASE_DRY_RUN=0
  RELEASE_YES=0
  RELEASE_NO_PUSH=0
  # Default skip: version bump + push first; CI runs verify once.
  RELEASE_SKIP_VERIFY=1
  RELEASE_SUMMARY=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        RELEASE_DRY_RUN=1
        shift
        ;;
      -y | --yes)
        RELEASE_YES=1
        shift
        ;;
      --no-push)
        RELEASE_NO_PUSH=1
        shift
        ;;
      --skip-verify)
        RELEASE_SKIP_VERIFY=1
        shift
        ;;
      --verify)
        RELEASE_SKIP_VERIFY=0
        shift
        ;;
      -h | --help)
        release_show_help "$0"
        exit 0
        ;;
      -*)
        echo "error: unknown option: $1" >&2
        release_show_help "$0"
        exit 1
        ;;
      *)
        if [[ -z "${RELEASE_SUMMARY}" ]]; then
          RELEASE_SUMMARY="$1"
        else
          RELEASE_SUMMARY="${RELEASE_SUMMARY} $1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "${RELEASE_SUMMARY}" ]]; then
    release_prompt_summary
  fi
}

release_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

release_prompt_summary() {
  if [[ -r /dev/tty ]]; then
    printf 'Release summary (one-line description): ' >/dev/tty
    IFS= read -r RELEASE_SUMMARY </dev/tty || true
  elif [[ -t 0 ]]; then
    printf 'Release summary (one-line description): '
    IFS= read -r RELEASE_SUMMARY || true
  fi
  RELEASE_SUMMARY="$(release_trim "${RELEASE_SUMMARY:-}")"
  if [[ -z "${RELEASE_SUMMARY}" ]]; then
    echo "error: release summary required (one-line description)" >&2
    release_show_help "$0"
    exit 1
  fi
}

release_push() {
  local tag="$1"

  if [[ "${RELEASE_NO_PUSH:-0}" == "1" ]]; then
    echo "Skipping push (--no-push)."
    echo "  git push origin main"
    echo "  git push origin ${tag}"
    return 0
  fi

  if [[ "${RELEASE_SKIP_VERIFY:-1}" == "1" ]]; then
    export OX_SKIP_VERIFY=1
  fi

  git push origin main
  git push origin "${tag}"
}

release_be_next_version() {
  local today max_n=0 n ver_date ver_n tag

  today="$(date +%Y.%m.%d)"

  if [[ -f VERSION ]]; then
    ver_date="$(tr -d '[:space:]' <VERSION | cut -d. -f1-3)"
    ver_n="$(tr -d '[:space:]' <VERSION | cut -d. -f4)"
    if [[ "${ver_date}" == "${today}" && "${ver_n}" =~ ^[0-9]+$ ]]; then
      max_n="${ver_n}"
    fi
  fi

  while read -r tag; do
    [[ -z "${tag}" ]] && continue
    n="${tag##*.}"
    if [[ "${n}" =~ ^[0-9]+$ ]] && (( n > max_n )); then
      max_n="${n}"
    fi
  done < <(git tag -l "v${today}.*" | sed 's/^v//')

  echo "${today}.$((max_n + 1))"
}

release_client_next_version() {
  local full name major minor patch new_patch

  full="$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//')"
  name="${full%%+*}"
  IFS=. read -r major minor patch <<<"${name}"
  new_patch=$((patch + 1))
  echo "${major}.${minor}.${new_patch}+${new_patch}"
}

release_client_version_name() {
  local full="$1"
  echo "${full%%+*}"
}

release_client_require_web_dispatch_token() {
  local has_gh=0

  if gh secret list --repo Gurbeh/oxplayer-client --json name -q '.[].name' 2>/dev/null \
    | grep -qx 'OXPLAYER_BE_DISPATCH_TOKEN'; then
    has_gh=1
  fi

  if [[ "${has_gh}" -eq 0 ]]; then
    echo "error: OXPLAYER_BE_DISPATCH_TOKEN is not set on Gurbeh/oxplayer-client." >&2
    echo "Release builds will fail at Deploy Web · Hetzner without it." >&2
    echo "" >&2
    echo "Fix (pick one):" >&2
    echo "  1. GitHub secret on Gurbeh/oxplayer-client:" >&2
    echo "       gh secret set OXPLAYER_BE_DISPATCH_TOKEN --repo Gurbeh/oxplayer-client" >&2
    echo "     (fine-grained PAT: Contents read + Actions read/write on Aryan-mor/oxplayer-be)" >&2
    echo "  2. Infisical /core/client-ci (preferred with other CI secrets):" >&2
    echo "       OXPLAYER_BE_DISPATCH_TOKEN=<same PAT>" >&2
    echo "       pnpm infisical:bootstrap-client-ci   # from oxplayer-be" >&2
    echo "" >&2
    echo "See oxplayer-client/docs/RELEASE.md § Web (Hetzner)." >&2
    exit 1
  fi
}
