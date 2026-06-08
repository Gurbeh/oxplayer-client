#!/usr/bin/env bash
# Retry a command with backoff. Usage: retry_command.sh <attempts> <delay_sec> -- <cmd...>
set -euo pipefail

attempts="${1:?attempts required}"
delay="${2:?delay required}"
shift 2
[[ "${1:-}" == "--" ]] && shift

for attempt in $(seq 1 "${attempts}"); do
  if "$@"; then
    exit 0
  fi
  if [[ "${attempt}" -eq "${attempts}" ]]; then
    exit 1
  fi
  echo "Command failed (attempt ${attempt}/${attempts}), retrying in ${delay}s..."
  sleep "${delay}"
done
