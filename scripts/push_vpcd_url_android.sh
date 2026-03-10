#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRINT_SCRIPT="$ROOT_DIR/scripts/print_vpcd_urls.sh"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found"
  exit 1
fi

URL="${VPCD_URL:-$("$PRINT_SCRIPT" | head -n 1)}"
if [[ -z "$URL" ]]; then
  echo "No vpcd:// URL available"
  exit 1
fi

adb start-server >/dev/null

STATE="$(adb get-state 2>/dev/null || true)"
if [[ "$STATE" != "device" ]]; then
  echo "No Android device connected over adb"
  exit 1
fi

adb shell am start \
  -a android.intent.action.VIEW \
  -d "$URL"

echo "Pushed $URL"
