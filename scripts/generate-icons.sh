#!/bin/bash
set -euo pipefail

# ── Generate AppIcon.icns from a source PNG ──────────────────────────
# Usage:  ./scripts/generate-icons.sh [source-png] [output-icns]
# Defaults:  assets/logo.png → Supporting/AppIcon.icns
# ───────────────────────────────────────────────────────────────────────

SRC="${1:-assets/logo.png}"
OUT="${2:-Supporting/AppIcon.icns}"

if [ ! -f "$SRC" ]; then
  echo "Error: source PNG not found: $SRC"
  exit 1
fi

echo "── Generating app icon from $SRC ──"

WORK_DIR="$(mktemp -d)"
ICONSET="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

# macOS required icon sizes
sips -z 16 16   "$SRC" --out "$ICONSET/icon_16x16.png"      &>/dev/null
sips -z 32 32   "$SRC" --out "$ICONSET/icon_16x16@2x.png"   &>/dev/null
sips -z 32 32   "$SRC" --out "$ICONSET/icon_32x32.png"      &>/dev/null
sips -z 64 64   "$SRC" --out "$ICONSET/icon_32x32@2x.png"   &>/dev/null
sips -z 128 128 "$SRC" --out "$ICONSET/icon_128x128.png"    &>/dev/null
sips -z 256 256 "$SRC" --out "$ICONSET/icon_128x128@2x.png" &>/dev/null
sips -z 256 256 "$SRC" --out "$ICONSET/icon_256x256.png"    &>/dev/null
sips -z 512 512 "$SRC" --out "$ICONSET/icon_256x256@2x.png" &>/dev/null
sips -z 512 512 "$SRC" --out "$ICONSET/icon_512x512.png"    &>/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONSET/icon_512x512@2x.png" &>/dev/null

# Convert iconset to .icns
iconutil -c icns "$ICONSET" -o "$OUT"

rm -rf "$WORK_DIR"
echo "── Done: $OUT ──"
