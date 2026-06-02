#!/bin/bash
# Build from the repo root (convenience wrapper around app/build-app.sh).
# Auto-detects variant from the current git branch.
#
# Usage: scripts/build.sh [debug|release] [variant]
set -euo pipefail
exec "$(dirname "$0")/../app/build-app.sh" "$@"
