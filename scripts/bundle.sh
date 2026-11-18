#!/bin/sh
# Builds the app and wraps it as build/MaxNines Desktop.app, which is what gives it
# a name, keeps it out of the Dock and lets it reach a server on the local network.
# It's MaxNines Desktop so it isn't taken for the agent or the server, but its
# menu and notifications still say MaxNines.
set -e
cd "$(dirname "$0")/.."
swift build -c release
app="build/MaxNines Desktop.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/MaxNinesMenuBar "$app/Contents/MacOS/MaxNines"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
# Which build this is, for Settings to show. A copy of the source with no git
# history still builds, as "unknown".
if commit=$(git rev-parse HEAD 2>/dev/null); then
    git diff --quiet HEAD || commit="$commit-dirty"
else
    commit=unknown
fi
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MaxNines Desktop</string>
    <key>CFBundleDisplayName</key><string>MaxNines</string>
    <key>CFBundleIdentifier</key><string>com.maxnines.menubar</string>
    <key>CFBundleExecutable</key><string>MaxNines</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>MaxNinesCommit</key><string>$commit</string>
    <key>MaxNinesBuiltAt</key><string>$built</string>
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
