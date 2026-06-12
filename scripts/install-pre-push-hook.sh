#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${ROOT}/.git/hooks/pre-push"

cat > "${HOOK}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
echo "pre-push: running verify-all.sh ..."
bash "${ROOT}/scripts/verify-all.sh"
EOF
chmod +x "${HOOK}"
echo "installed ${HOOK}"
