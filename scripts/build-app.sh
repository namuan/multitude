#!/bin/bash
set -euo pipefail

# ── Build and package Multitude into a proper .app bundle ────────────
# Without a .app bundle, macOS will never prompt for camera/mic permissions
# because it reads NSCameraUsageDescription / NSMicrophoneUsageDescription
# from the bundle's Info.plist.
#
# Usage:
#   ./scripts/build-app.sh              # build + create .app
#   ./scripts/build-app.sh --run        # build + create .app + launch
#   ./scripts/build-app.sh -r           # same as --run

PRODUCT="Multitude"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
APP_BUNDLE="$BUILD_DIR/$PRODUCT.app"
BINARY_PATH="$BUILD_DIR/debug/$PRODUCT"

DO_RUN=false
for arg in "$@"; do
    case "$arg" in
        --run|-r) DO_RUN=true ;;
    esac
done

echo "── Building $PRODUCT ──"
swift build --configuration debug

echo "── Creating $APP_BUNDLE ──"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp "$REPO_ROOT/Supporting/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "── Done ──"
echo ""

if [ "$DO_RUN" = true ]; then
    echo "── Launching $PRODUCT ──"
    open "$APP_BUNDLE"
else
    echo "Run with:  open '$APP_BUNDLE'"
    echo "Or:        ./scripts/build-app.sh --run"
fi
