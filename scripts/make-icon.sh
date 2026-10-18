#!/bin/zsh
# Regenerates Resources/AppIcon.icns (and docs/icon.png) from scripts/make-icon.swift.
set -euo pipefail

ROOT=${0:A:h:h}
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET" "$ROOT/docs"

swift "$ROOT/scripts/make-icon.swift" "$TMP/icon-1024.png"

for size in 16 32 128 256 512; do
  sips -z $size $size "$TMP/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$TMP/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
sips -z 256 256 "$TMP/icon-1024.png" --out "$ROOT/docs/icon.png" >/dev/null
echo "Wrote Resources/AppIcon.icns and docs/icon.png"
