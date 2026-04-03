#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Zapi"
PRODUCT_NAME="ZapiApp"
BUILD_DIR="$ROOT_DIR/.build"
APP_BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE_SOURCE="$BUILD_DIR/arm64-apple-macosx/debug/$PRODUCT_NAME"
EXECUTABLE_DEST="$APP_BUNDLE_DIR/Contents/MacOS/$PRODUCT_NAME"
INFO_PLIST_SOURCE="$ROOT_DIR/App/Info.plist"
INFO_PLIST_DEST="$APP_BUNDLE_DIR/Contents/Info.plist"

mkdir -p "$ROOT_DIR/dist"

export HOME="$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"

cd "$ROOT_DIR"
swift build --product "$PRODUCT_NAME" --scratch-path .build

rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources"

cp "$EXECUTABLE_SOURCE" "$EXECUTABLE_DEST"
chmod +x "$EXECUTABLE_DEST"
cp "$INFO_PLIST_SOURCE" "$INFO_PLIST_DEST"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$INFO_PLIST_DEST" >/dev/null
fi

echo "Built app bundle at:"
echo "$APP_BUNDLE_DIR"
