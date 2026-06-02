#!/bin/bash
# Stop the running VellumX variant for the current branch, rebuild, and relaunch.
#
# Usage: scripts/restart.sh [debug|release]   (default: debug)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# Derive variant from branch — same logic as app/build-app.sh.
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || [ -z "$BRANCH" ]; then
    VARIANT=""
else
    VARIANT="$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
fi

APP_NAME="${VARIANT:+VellumX-$VARIANT}"
APP_NAME="${APP_NAME:-VellumX}"
BUNDLE_ID="${VARIANT:+com.ailuras.vellumx.$VARIANT}"
BUNDLE_ID="${BUNDLE_ID:-com.ailuras.vellumx}"
APP_PATH="$REPO/app/${APP_NAME}.app"
CONFIG="${1:-debug}"

echo "branch: ${BRANCH:-<none>}  →  $APP_NAME ($CONFIG)"

# Graceful quit via bundle ID, then hard-kill any survivor.
echo "[1/3] stopping $APP_NAME..."
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 0.8
pkill -f "${APP_NAME}.app/Contents/MacOS" 2>/dev/null || true

echo "[2/3] building..."
"$REPO/app/build-app.sh" "$CONFIG"

echo "[3/3] launching $APP_PATH (right screen)"
defaults write com.ailuras.vellumx launchOnRightScreen -bool true
open "$APP_PATH"
