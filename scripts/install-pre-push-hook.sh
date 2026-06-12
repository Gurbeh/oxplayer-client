#!/usr/bin/env bash
# Enable required pre-push verification (scripts/verify-all.sh blocks push on failure).
#
# Run once after clone:
#   bash scripts/install-pre-push-hook.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${ROOT}/scripts/git-hooks"
HOOK_SRC="${HOOKS_DIR}/pre-push"
HOOK_DST="${ROOT}/.git/hooks/pre-push"

if [[ ! -f "${HOOK_SRC}" ]]; then
  echo "error: missing ${HOOK_SRC}" >&2
  exit 1
fi

chmod +x "${HOOK_SRC}"

mkdir -p "${ROOT}/.git/hooks"
cat > "${HOOK_DST}" <<EOF
#!/usr/bin/env bash
exec bash "${HOOK_SRC}" "\$@"
EOF
chmod +x "${HOOK_DST}"

echo "required pre-push hook installed: ${HOOK_DST}"
echo "Every git push will run scripts/verify-all.sh first."
