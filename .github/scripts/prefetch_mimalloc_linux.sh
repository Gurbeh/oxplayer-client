#!/usr/bin/env bash
# Pre-fetch mimalloc for media_kit_libs_linux with retries and optional CI cache seeding.
set -euo pipefail

MIMALLOC_URL="https://github.com/microsoft/mimalloc/archive/refs/tags/v2.1.2.tar.gz"
MIMALLOC_MD5="5179c8f5cf1237d2300e2d8559a7bc55"
DEST="build/linux/x64/release/mimalloc-2.1.2.tar.gz"
CACHE=".ci-cache/mimalloc-2.1.2.tar.gz"

mkdir -p build/linux/x64/release .ci-cache

verify_md5() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(md5sum "${file}" | awk '{print $1}')"
  [[ "${actual}" == "${expected}" ]]
}

if [[ -f "${DEST}" ]] && verify_md5 "${DEST}" "${MIMALLOC_MD5}"; then
  echo "mimalloc archive already present and valid."
  exit 0
fi

if [[ -f "${CACHE}" ]] && verify_md5 "${CACHE}" "${MIMALLOC_MD5}"; then
  echo "Seeding mimalloc from CI cache."
  cp "${CACHE}" "${DEST}"
  exit 0
fi

rm -f "${DEST}" "${CACHE}"
for attempt in 1 2 3 4 5; do
  echo "Downloading mimalloc (attempt ${attempt}/5)..."
  if curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 \
    -o "${DEST}.tmp" "${MIMALLOC_URL}" && verify_md5 "${DEST}.tmp" "${MIMALLOC_MD5}"; then
    mv "${DEST}.tmp" "${DEST}"
    cp "${DEST}" "${CACHE}"
    echo "mimalloc download verified."
    exit 0
  fi
  rm -f "${DEST}.tmp"
  if [[ "${attempt}" -lt 5 ]]; then
    sleep $((attempt * 15))
  fi
done

echo "Failed to download a valid mimalloc archive."
exit 1
