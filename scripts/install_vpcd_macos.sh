#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAGE_DIR="$ROOT_DIR/build/vsmartcard-stage/usr/local"
BUNDLE_SRC="$STAGE_DIR/libexec/SmartCardServices/drivers/ifd-vpcd.bundle"
HELPER_SRC="$STAGE_DIR/bin/vpcd-config"
BUNDLE_DST="/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle"
HELPER_DST="/usr/local/bin/vpcd-config"

if [[ ! -d "$BUNDLE_SRC" ]]; then
  echo "Staged bundle not found: $BUNDLE_SRC"
  echo "Build it first with:"
  echo "  bash ./mynumber-bridge/scripts/build_vpcd_macos.sh"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo to install the macOS smart card bundle..."
  exec sudo "$0" "$@"
fi

mkdir -p /usr/local/libexec/SmartCardServices/drivers
rm -rf "$BUNDLE_DST"
cp -R "$BUNDLE_SRC" "$BUNDLE_DST"
install -m 755 "$HELPER_SRC" "$HELPER_DST"
MAIN_EXEC="$BUNDLE_DST/Contents/MacOS/libifdvpcd.dylib"
if [[ -L "$MAIN_EXEC" ]]; then
  TARGET_PATH="$(readlink "$MAIN_EXEC")"
  rm "$MAIN_EXEC"
  cp "$BUNDLE_DST/Contents/MacOS/$TARGET_PATH" "$MAIN_EXEC"
  chmod 755 "$MAIN_EXEC"
fi
codesign -s - --force --deep "$BUNDLE_DST"

killall -SIGKILL -m '.*com.apple.ifdreader' 2>/dev/null || true

echo "Installed:"
echo "  $BUNDLE_DST"
echo "  $HELPER_DST"
echo
echo "Next:"
echo "  system_profiler SPSmartCardsDataType"
echo "  /usr/local/bin/vpcd-config"
