#!/bin/sh
# Builds the app and wraps it as build/MaxNines.app, which is what gives it a
# name, keeps it out of the Dock and lets it reach a server on the local network.
set -e
cd "$(dirname "$0")/.."
swift build -c release
app=build/MaxNines.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/MaxNinesMenuBar "$app/Contents/MacOS/MaxNines"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MaxNines</string>
    <key>CFBundleDisplayName</key><string>MaxNines</string>
    <key>CFBundleIdentifier</key><string>com.maxnines.menubar</string>
    <key>CFBundleExecutable</key><string>MaxNines</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
echo "Built $app"
