#!/bin/zsh
# Builds "Dock Dividers.app" (Apple Silicon + Intel), installs it to /Applications
# and writes website/public/DockDividers.zip for the download page.
set -e
cd "$(dirname "$0")"
# Built outside iCloud Desktop: its file provider re-adds xattrs that break codesign.
BUILD=$(mktemp -d); APP="$BUILD/Dock Dividers.app"
mkdir -p "$APP/Contents/MacOS"
for arch in arm64 x86_64; do
  xcrun swiftc -O -parse-as-library -target $arch-apple-macos13.0 main.swift -o "$BUILD/DockDividers-$arch"
done
lipo -create "$BUILD"/DockDividers-* -output "$APP/Contents/MacOS/DockDividers"
mkdir -p "$APP/Contents/Resources" && cp AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dock Dividers</string>
  <key>CFBundleIdentifier</key><string>com.armanalis.dockdividers</string>
  <key>CFBundleExecutable</key><string>DockDividers</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
# A stable local identity keeps the Accessibility permission across rebuilds; ad-hoc resets it.
ID=$(security find-identity -p codesigning | awk '/Dock Dividers Local Signing/{print $2; exit}')
codesign --force -s "${ID:--}" "$APP"
rm -rf "/Applications/Dock Dividers.app" && cp -R "$APP" /Applications/
# Re-register so Spotlight/Launchpad pick up a new icon instead of a cached blank one.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Dock Dividers.app"
[ -z "$ID" ] && echo "Note: ad-hoc signed; the Accessibility permission resets on every build."
mkdir -p website/public && (cd "$BUILD" && ditto -c -k --keepParent "Dock Dividers.app" DockDividers.zip)
cp "$BUILD/DockDividers.zip" website/public/DockDividers.zip
echo "Installed /Applications/Dock Dividers.app and wrote website/public/DockDividers.zip"
