#!/usr/bin/env bash
# Bump pubspec.yaml + Play changelog, commit, tag vM.m.p, push main + tag.
# Usage: bash scripts/release-client.sh [options] ["One-line release summary"]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release-common.sh
source "${SCRIPT_DIR}/release-common.sh"

release_show_help() {
  cat <<'EOF'
Usage: release-client.sh [options] [summary]

Semver bump (patch) in pubspec.yaml + fastlane changelog.
Summary is prompted if omitted.
Tag: vM.m.p → triggers Build OXPlayer (signed AAB + GitHub draft release).

Options:
  --dry-run      Show plan only
  -y, --yes      Skip confirmation
  --no-push      Commit and tag locally only
  --skip-verify  Default: skip local verify (CI is the gate)
  --verify       Run verify-all locally before push

Example:
  bash scripts/release-client.sh -y "Iran web API routing fixes"
  # Both repos: from oxplayer-be → pnpm release:all -y "…"
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  release_show_help
  exit 0
fi

release_parse_args "$@"
cd "${SCRIPT_DIR}/.."
ROOT="$(release_root)"
cd "${ROOT}"

release_require_gh_auth
release_commit_pending_changes
release_preflight
release_client_require_web_dispatch_token
release_run_verify

NEW_VERSION="$(release_client_next_version)"
VERSION_NAME="$(release_client_version_name "${NEW_VERSION}")"
TAG="v${VERSION_NAME}"
CHANGELOG="fastlane/metadata/android/en-US/changelogs/${VERSION_NAME}.txt"

if git rev-parse "${TAG}" &>/dev/null; then
  echo "error: tag ${TAG} already exists" >&2
  exit 1
fi

release_confirm "${RELEASE_SUMMARY}" "${VERSION_NAME}" "${TAG}"

if [[ "${RELEASE_DRY_RUN}" == "1" ]]; then
  echo "[dry-run] Would set pubspec.yaml version: ${NEW_VERSION}"
  echo "[dry-run] Would write ${CHANGELOG}"
  echo "[dry-run] Would commit, tag ${TAG}, push main + tag"
  exit 0
fi

sed -i.bak "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
rm -f pubspec.yaml.bak

mkdir -p "$(dirname "${CHANGELOG}")"
printf '%s\n' "${RELEASE_SUMMARY}" >"${CHANGELOG}"

git add pubspec.yaml "${CHANGELOG}"

SUBJECT="Release ${VERSION_NAME}: ${RELEASE_SUMMARY}."

git commit -m "$(cat <<EOF
${SUBJECT}

${RELEASE_SUMMARY}.
EOF
)"

git tag -a "${TAG}" -m "${SUBJECT}"

release_push "${TAG}"

echo ""
echo "=== released ${VERSION_NAME} (${TAG}) ==="
echo "Watch build:"
echo "  gh run list --repo Gurbeh/oxplayer-client --workflow='Build OXPlayer' --limit 3"
echo "  gh run watch --repo Gurbeh/oxplayer-client"
echo ""
echo "When Create Release is green, publish draft:"
echo "  gh release edit ${TAG} --repo Gurbeh/oxplayer-client --draft=false"
