#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/pkg"
APP_PATH="$ROOT_DIR/build/mac-app/MyNumber Bridge.app"
PKGROOT_DIR="$BUILD_DIR/pkgroot"
OUTPUT_PKG="$BUILD_DIR/MyNumber-Bridge-macos-beta.pkg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH"
  echo "Build it first with:"
  echo "  bash ./scripts/build_menubar_app_macos.sh"
  exit 1
fi

rm -rf "$PKGROOT_DIR" "$OUTPUT_PKG"
mkdir -p "$PKGROOT_DIR/Applications"
cp -R "$APP_PATH" "$PKGROOT_DIR/Applications/"

pkgbuild \
  --root "$PKGROOT_DIR" \
  --identifier "jp.mojashi.mynumber-bridge.app" \
  --version "0.1" \
  --install-location "/" \
  "$OUTPUT_PKG" >/dev/null

echo "$OUTPUT_PKG"
