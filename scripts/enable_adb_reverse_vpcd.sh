#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRINT_SCRIPT="$ROOT_DIR/scripts/print_vpcd_urls.sh"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found"
  exit 1
fi

URLS="$("$PRINT_SCRIPT")"
if [[ -z "$URLS" ]]; then
  echo "No vpcd:// URLs available"
  exit 1
fi

adb start-server >/dev/null

while IFS= read -r url; do
  [[ -z "$url" ]] && continue
  port="${url##*:}"
  adb reverse "tcp:$port" "tcp:$port"
  echo "adb reverse tcp:$port tcp:$port"
done <<< "$URLS"
