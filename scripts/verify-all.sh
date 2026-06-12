#!/usr/bin/env bash
# Static checks before pushing oxplayer-client (catches compile errors CI would hit).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "=== oxplayer-client verify-all ==="
flutter pub get

analyze_log="$(mktemp)"
trap 'rm -f "${analyze_log}"' EXIT
set +e
dart analyze lib/ 2>&1 | tee "${analyze_log}"
analyze_exit=$?
set -e

if grep -qE '^[[:space:]]*error -' "${analyze_log}"; then
  echo "verify-all failed: dart analyze reported errors (see above)"
  exit 1
fi
if [[ "${analyze_exit}" -gt 2 ]]; then
  echo "verify-all failed: dart analyze exited ${analyze_exit}"
  exit 1
fi

echo "=== verify-all OK ==="
