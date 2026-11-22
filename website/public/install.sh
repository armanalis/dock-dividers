#!/bin/sh
# Dock Dividers installer for macOS.
# Usage: curl -fsSL https://dock-dividers.armanalis.workers.dev/install.sh | sh
# Files downloaded with curl are not quarantined, so macOS doesn't show the "could not verify" warning.
set -e

URL="https://dock-dividers.armanalis.workers.dev/DockDividers.zip"
APP="Dock Dividers.app"

# admins can write to /Applications; standard users get ~/Applications
if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; mkdir -p "$DEST"; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Dock Dividers indiriliyor..."
curl -fsSL "$URL" -o "$TMP/DockDividers.zip"
ditto -x -k "$TMP/DockDividers.zip" "$TMP/out"
[ -d "$TMP/out/$APP" ] || { echo "Hata: indirilen dosya bozuk."; exit 1; }

osascript -e 'quit app "Dock Dividers"' >/dev/null 2>&1 || true
rm -rf "$DEST/$APP"   # replace an older version of this app only
ditto "$TMP/out/$APP" "$DEST/$APP"
xattr -dr com.apple.quarantine "$DEST/$APP" 2>/dev/null || true

echo "Kuruldu: $DEST/$APP"
open "$DEST/$APP"
