#!/usr/bin/env bash

set -euo pipefail

if [[ "${LC_ALL:-}" == "C.UTF-8" ]]; then
  unset LC_ALL
fi
export LANG="en_US.UTF-8"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGED_VPCD_CONFIG="$ROOT_DIR/build/vsmartcard-stage/usr/local/bin/vpcd-config"

if [[ -x "$STAGED_VPCD_CONFIG" ]]; then
  "$STAGED_VPCD_CONFIG" | sed -n 's#.*\(vpcd://[^[:space:]]*\).*#\1#p'
  exit 0
fi

if command -v vpcd-config >/dev/null 2>&1; then
  vpcd-config | sed -n 's#.*\(vpcd://[^[:space:]]*\).*#\1#p'
  exit 0
fi

echo "vpcd-config not found. Build it first with:"
echo "  bash ./mynumber-bridge/scripts/build_vpcd_macos.sh"
exit 1
