#!/bin/bash
# Builds a release binary and wraps it into BambuBar.app (menu bar only, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/BambuBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BambuBar "$APP/Contents/MacOS/BambuBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BambuBar</string>
<key>CFBundleIdentifier</key><string>dev.kopytjuk.bambubar</string>
<key>CFBundleExecutable</key><string>BambuBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>BambuBar verbindet sich mit deinem Bambu-Lab-Drucker im lokalen Netzwerk.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
