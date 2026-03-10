#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/bluetooth-helper"
SOURCE_FILE="$ROOT_DIR/bluetooth-helper/rfcomm_vpcd_bridge.m"
OUTPUT_FILE="$BUILD_DIR/rfcomm-vpcd-bridge"
SDKROOT_DEFAULT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
SDKROOT_VALUE="${SDKROOT:-$SDKROOT_DEFAULT}"

if [[ ! -d "$SDKROOT_VALUE" ]]; then
  SDKROOT_VALUE="$SDKROOT_DEFAULT"
fi

mkdir -p "$BUILD_DIR"

env -u DEVELOPER_DIR -u SDKROOT clang \
  -fobjc-arc \
  -Wall \
  -Wextra \
  -isysroot "$SDKROOT_VALUE" \
  -framework Foundation \
  -framework IOBluetooth \
  "$SOURCE_FILE" \
  -o "$OUTPUT_FILE"

echo "$OUTPUT_FILE"
