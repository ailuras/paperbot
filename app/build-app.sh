#!/bin/bash
# Build VellumX.app via SwiftPM, wrap the binary into a code-signed .app bundle.
#
# Usage: ./build-app.sh [debug|release] [variant]
#   variant  optional; defaults to the current git branch (empty on main/master).
#            e.g. branch "feat/pdf" → VellumX-feat-pdf.app
#            with bundle ID com.ailuras.vellumx.feat-pdf; shares the main data dir.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"

# Auto-detect variant from git branch when not supplied explicitly.
# main/master → no variant (builds the canonical VellumX.app).
# Sanitise: lowercase, collapse any run of non-alphanumeric chars to a single dash,
# strip leading/trailing dashes (bundle IDs must not start/end with a dot segment).
if [ $# -ge 2 ]; then
    VARIANT="${2}"
else
    BRANCH="$(git -C "$(dirname "$0")" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || [ -z "$BRANCH" ]; then
        VARIANT=""
    else
        VARIANT="$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
    fi
fi

APP="${VARIANT:+VellumX-$VARIANT.app}"
APP="${APP:-VellumX.app}"
BIN_NAME="VellumX"

echo "[1/4] swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"

echo "[2/4] assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"
if [ -n "$VARIANT" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ailuras.vellumx.$VARIANT" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName VellumX-$VARIANT" "$APP/Contents/Info.plist"
fi
[ -f Resources/VellumX.icns ] && cp Resources/VellumX.icns "$APP/Contents/Resources/VellumX.icns"
[ -f Resources/MenuBarIcon.png ] && cp Resources/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
[ -f Resources/MenuBarIcon@2x.png ] && cp "Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/MenuBarIcon@2x.png"

echo "[3/4] codesign (ad-hoc, with entitlements)"
codesign --force --sign - \
  --entitlements VellumX.entitlements \
  --options runtime \
  "$APP"

echo "[4/4] done -> $APP"
echo "run:  open ./$APP"
[ -n "$VARIANT" ] && echo "note: bundle ID = com.ailuras.vellumx.$VARIANT (shares ~/Library/Application Support/VellumX/)"
