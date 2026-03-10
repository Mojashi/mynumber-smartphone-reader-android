#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_SCRIPT="$ROOT_DIR/nta_chrome_ext_host.py"
MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$MANIFEST_DIR/nta.chrome.ext.json"
EXTENSION_ID="${1:-hopiajgbpnepghlkfmdonpgdnmcajpeb}"

if [[ "${1:-}" == "--extension-id" ]]; then
  EXTENSION_ID="${2:?missing extension id}"
fi

mkdir -p "$MANIFEST_DIR"
chmod 755 "$HOST_SCRIPT"

cat > "$MANIFEST_PATH" <<EOF
{
  "name": "nta.chrome.ext",
  "description": "e-Tax AP native host probe for macOS",
  "path": "$HOST_SCRIPT",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$EXTENSION_ID/"
  ]
}
EOF

echo "Installed native host manifest:"
echo "  $MANIFEST_PATH"
echo
echo "Host script:"
echo "  $HOST_SCRIPT"
echo
echo "Log file:"
echo "  $HOME/Library/Logs/mynumber-bridge/nta.chrome.ext.log"
