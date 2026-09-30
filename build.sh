#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/GlobalProtect Toggle.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx12.0 Sources/ServiceController.swift Sources/VPNDisconnector.swift Sources/Permissions.swift Sources/main.swift -o "$APP/Contents/MacOS/GlobalProtectToggle" -framework AppKit
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GlobalProtectToggle</string>
<key>CFBundleIdentifier</key><string>local.radek.GlobalProtectToggle</string>
<key>CFBundleName</key><string>GlobalProtect Toggle</string>
<key>CFBundleDisplayName</key><string>GlobalProtect Toggle</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Local utility. GlobalProtect and its original icon belong to Palo Alto Networks.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/build/GlobalProtect-Toggle.zip"
printf 'Built: %s\n' "$APP"
