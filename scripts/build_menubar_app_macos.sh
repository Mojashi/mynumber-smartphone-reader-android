#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/mac-app"
APP_NAME="MyNumber Bridge.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
EXECUTABLE_NAME="MyNumberBridgeStatusApp"
if [[ -n "${SDKROOT:-}" && -d "${SDKROOT}" ]]; then
  SDKROOT_VALUE="${SDKROOT}"
else
  SDKROOT_VALUE="$(env -u DEVELOPER_DIR -u SDKROOT xcrun --sdk macosx --show-sdk-path)"
fi

HELPER_PATH="$(bash "$ROOT_DIR/scripts/build_rfcomm_client_macos.sh")"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

env -u DEVELOPER_DIR -u SDKROOT xcrun swiftc \
  -sdk "$SDKROOT_VALUE" \
  -target arm64-apple-macos13.0 \
  -framework AppKit \
  -framework IOBluetooth \
  -framework WebKit \
  "$ROOT_DIR/mac-app/main.swift" \
  -o "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

cp "$ROOT_DIR/mac-app/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$HELPER_PATH" "$APP_DIR/Contents/Resources/rfcomm-vpcd-client"
rm -rf "$APP_DIR/Contents/Resources/ui"
cp -R "$ROOT_DIR/mac-app/ui" "$APP_DIR/Contents/Resources/ui"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" "$APP_DIR/Contents/Resources/rfcomm-vpcd-client"

codesign --force --sign - --deep "$APP_DIR" >/dev/null 2>&1 || true

echo "$APP_DIR"
