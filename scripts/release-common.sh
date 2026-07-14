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

release_require_gh_auth() {
  release_require_cmd gh git
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
  git fetch origin --tags
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
  if [[ "${RELEASE_SKIP_VERIFY:-0}" == "1" ]]; then
    echo "Skipping verify-all (--skip-verify)"
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
Usage: ${script_name} [options] <summary>

Options:
  --dry-run      Show plan only; no file edits
  -y, --yes      Skip confirmation prompt
  --no-push      Commit and tag locally only
  --skip-verify  Skip scripts/verify-all.sh and pre-push verify (OX_SKIP_VERIFY=1)

Requires: gh auth login, clean main, up to date with origin/main
EOF
}

release_parse_args() {
  RELEASE_DRY_RUN=0
  RELEASE_YES=0
  RELEASE_NO_PUSH=0
  RELEASE_SKIP_VERIFY=0
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

  if [[ "${RELEASE_SKIP_VERIFY:-0}" == "1" ]]; then
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
