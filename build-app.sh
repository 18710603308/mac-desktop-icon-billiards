#!/bin/bash
# Builds DesktopIconBilliards.app (release binary + Info.plist + icon + ad-hoc signature).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product DesktopIconBilliards
BIN=.build/release/DesktopIconBilliards

APP=build/DesktopIconBilliards.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DesktopIconBilliards"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DesktopIconBilliards</string>
    <key>CFBundleDisplayName</key><string>桌面图标台球</string>
    <key>CFBundleIdentifier</key><string>com.liuxiaogang.desktopiconbilliards</string>
    <key>CFBundleExecutable</key><string>DesktopIconBilliards</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# App icon: render a 1024 master, derive the iconset, compile to .icns.
mkdir -p build
swiftc -O tools/makeicon.swift -o build/makeicon
./build/makeicon build/icon_1024.png
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
cp build/icon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so the app launches without Gatekeeper quarantine friction.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"