#!/bin/bash
set -euo pipefail

# ── Multitude install script ─────────────────────────────────────────
# Builds a release binary, wraps it in a proper .app bundle (required for
# camera/microphone permissions), and installs it to ~/Applications.
#
# Usage:
#   ./install.command               # build release, install, launch
#   ./install.command --debug       # build debug instead
# ──────────────────────────────────────────────────────────────────────

# Require only Xcode Command Line Tools — full Xcode is NOT needed.
if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found."
  echo "Install Xcode Command Line Tools:"
  echo "  xcode-select --install"
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Error: No active developer directory found."
  echo "Run: xcode-select --install"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Multitude"
BUILD_MODE="release"
[[ "${1:-}" == "--debug" ]] && BUILD_MODE="debug"

DERIVED="$ROOT/.build"
BINARY="$DERIVED/$BUILD_MODE/$APP_NAME"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"

echo "── Building $APP_NAME ($BUILD_MODE) ──"
swift build -c "$BUILD_MODE"

if [ ! -f "$BINARY" ]; then
  echo "Error: Build succeeded but binary not found at: $BINARY"
  exit 1
fi

echo "── Creating $DEST_APP ──"
rm -rf "$DEST_APP"
mkdir -p "$DEST_APP/Contents/MacOS" "$DEST_APP/Contents/Resources"

cp "$BINARY" "$DEST_APP/Contents/MacOS/$APP_NAME"
chmod +x "$DEST_APP/Contents/MacOS/$APP_NAME"

# Use the Info.plist from the Supporting directory (includes camera/mic keys)
cp "$ROOT/Supporting/Info.plist" "$DEST_APP/Contents/Info.plist"

echo "── Installed to $DEST_APP ──"
echo ""
open "$DEST_APP"
