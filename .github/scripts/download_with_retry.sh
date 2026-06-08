#!/usr/bin/env bash
# Usage: download_with_retry.sh <url> <dest> [attempts] [base_delay_sec]
set -euo pipefail

url="${1:?url required}"
dest="${2:?dest required}"
attempts="${3:-8}"
base_delay="${4:-15}"

mkdir -p "$(dirname "${dest}")"

for attempt in $(seq 1 "${attempts}"); do
  if curl -fsSL --connect-timeout 30 --max-time 900 -o "${dest}.tmp" "${url}"; then
    mv "${dest}.tmp" "${dest}"
    echo "Downloaded ${url}"
    exit 0
  fi
  rm -f "${dest}.tmp"
  echo "Download failed (attempt ${attempt}/${attempts}): ${url}"
  if [[ "${attempt}" -lt "${attempts}" ]]; then
    sleep $((attempt * base_delay))
  fi
done

echo "Giving up on ${url}"
exit 1
