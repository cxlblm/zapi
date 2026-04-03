#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE_DIR="$ROOT_DIR/dist/Zapi.app"

"$ROOT_DIR/Scripts/build-app.sh"
open "$APP_BUNDLE_DIR"
