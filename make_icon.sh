#!/bin/zsh
# Regenerates AppIcon.icns from make_icon.swift. Only needed when the icon design changes.
set -e
cd "$(dirname "$0")"
TMP=$(mktemp -d)
xcrun swift make_icon.swift "$TMP/icon.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o AppIcon.icns
sips -z 256 256 "$TMP/icon.png" --out icon-preview.png >/dev/null
echo "Wrote AppIcon.icns"
