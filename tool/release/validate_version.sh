#!/usr/bin/env bash
# Validates pubspec version before GitHub tag or Google Play upload.
# Ledger: fastlane/metadata/android/en-US/changelogs/{versionCode}.txt
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PUBSPEC="$ROOT/pubspec.yaml"
CHANGELOG_DIR="$ROOT/fastlane/metadata/android/en-US/changelogs"
FOR_TAG=false

for arg in "$@"; do
  case "$arg" in
    --for-tag) FOR_TAG=true ;;
    -h | --help)
      echo "Usage: $0 [--for-tag]"
      echo "  --for-tag  Also fail when git tag v{versionName} already exists."
      exit 0
      ;;
  esac
done

if [ ! -f "$PUBSPEC" ]; then
  echo "ERROR: pubspec.yaml not found at $PUBSPEC"
  exit 1
fi

FULL_VERSION="$(grep '^version: ' "$PUBSPEC" | sed 's/version: //' | tr -d ' ')"
if [[ ! "$FULL_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "ERROR: pubspec version must be NAME+BUILD (e.g. 0.0.4+8), got: $FULL_VERSION"
  exit 1
fi

VERSION_NAME="${FULL_VERSION%%+*}"
BUILD_NUMBER="${FULL_VERSION#*+}"

MAX_LEDGER=0
if [ -d "$CHANGELOG_DIR" ]; then
  for file in "$CHANGELOG_DIR"/*.txt; do
    [ -f "$file" ] || continue
    base="$(basename "$file" .txt)"
    [[ "$base" =~ ^[0-9]+$ ]] || continue
    if [ "$base" -gt "$MAX_LEDGER" ]; then
      MAX_LEDGER="$base"
    fi
  done
fi

if [ "$BUILD_NUMBER" -le "$MAX_LEDGER" ]; then
  echo "ERROR: versionCode $BUILD_NUMBER is not greater than Play ledger max ($MAX_LEDGER)."
  echo "       Bump pubspec to ${VERSION_NAME}+$((MAX_LEDGER + 1)) (or higher) before release."
  exit 1
fi

if [ "$FOR_TAG" = true ]; then
  git -C "$ROOT" fetch --tags origin 2>/dev/null || true
  if git -C "$ROOT" rev-parse "v${VERSION_NAME}" >/dev/null 2>&1; then
    echo "ERROR: Git tag v${VERSION_NAME} already exists."
    echo "       Bump version name in pubspec, or push a versionCode-only fix to main and run"
    echo "       Build OXPlayer (workflow_dispatch, build_type=release) for Play-only upload."
    exit 1
  fi
fi

echo "OK: ${VERSION_NAME}+${BUILD_NUMBER} (Play ledger max: ${MAX_LEDGER})"
