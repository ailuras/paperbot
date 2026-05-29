#!/bin/bash
# Build PaperBot.app via SwiftPM, wrap the binary into a code-signed .app bundle.
#
# Usage: ./build-app.sh [debug|release] && open ./PaperBot.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="PaperBot.app"
BIN_NAME="PaperBot"

echo "[1/4] swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "[2/4] assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"

echo "[3/4] codesign (ad-hoc, with entitlements)"
codesign --force --sign - \
  --entitlements PaperBot.entitlements \
  --options runtime \
  "$APP"

echo "[4/4] done -> $APP"
echo "run:  open ./$APP"
