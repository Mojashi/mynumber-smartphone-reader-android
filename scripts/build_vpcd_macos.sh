#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
SRC_DIR="$BUILD_DIR/vsmartcard"
VSMARTCARD_DIR="$SRC_DIR/virtualsmartcard"
STAGE_DIR="$BUILD_DIR/vsmartcard-stage"
VSMARTCARD_REPO="${VSMARTCARD_REPO:-https://github.com/frankmorgner/vsmartcard.git}"
VSMARTCARD_REF="${VSMARTCARD_REF:-master}"

mkdir -p "$BUILD_DIR"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  git clone --depth 1 --branch "$VSMARTCARD_REF" "$VSMARTCARD_REPO" "$SRC_DIR"
else
  git -C "$SRC_DIR" fetch --depth 1 origin "$VSMARTCARD_REF"
  git -C "$SRC_DIR" checkout "$VSMARTCARD_REF"
  git -C "$SRC_DIR" reset --hard "origin/$VSMARTCARD_REF"
fi

SDKROOT="$(env -u DEVELOPER_DIR xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
export LANG="en_US.UTF-8"
if [[ "${LC_ALL:-}" == "C.UTF-8" ]]; then
  unset LC_ALL
fi
export CPPFLAGS="-I$SDKROOT/System/Library/Frameworks/PCSC.framework/Versions/A/Headers -DRESPONSECODE_DEFINED_IN_WINTYPES_H -I$VSMARTCARD_DIR/MacOSX"
export LDFLAGS="-isysroot $SDKROOT"

pushd "$VSMARTCARD_DIR" >/dev/null
env -u DEVELOPER_DIR autoreconf -vis
env -u DEVELOPER_DIR ./configure --enable-infoplist CC="clang -isysroot $SDKROOT"
env -u DEVELOPER_DIR make -j"$(sysctl -n hw.ncpu)"
rm -rf "$STAGE_DIR"
env -u DEVELOPER_DIR make install DESTDIR="$STAGE_DIR"

STAGED_BUNDLE="$STAGE_DIR/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle"
if [[ -d "$STAGED_BUNDLE" ]]; then
  MAIN_EXEC="$STAGED_BUNDLE/Contents/MacOS/libifdvpcd.dylib"
  if [[ -L "$MAIN_EXEC" ]]; then
    TARGET_PATH="$(readlink "$MAIN_EXEC")"
    rm "$MAIN_EXEC"
    cp "$STAGED_BUNDLE/Contents/MacOS/$TARGET_PATH" "$MAIN_EXEC"
    chmod 755 "$MAIN_EXEC"
  fi
  codesign -s - --force --deep "$STAGED_BUNDLE"
fi
popd >/dev/null

cat <<EOF
Staged vpcd build is ready.

Bundle:
  $STAGE_DIR/usr/local/libexec/SmartCardServices/drivers/ifd-vpcd.bundle

Helper:
  $STAGE_DIR/usr/local/bin/vpcd-config

Next:
  1. Run ./mynumber-bridge/scripts/list_usb_ids.sh
  2. Patch Info.plist with ./mynumber-bridge/scripts/render_info_plist.py
  3. Install the staged bundle manually into /usr/local/libexec/SmartCardServices
EOF
