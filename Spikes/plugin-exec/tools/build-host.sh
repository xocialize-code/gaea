#!/bin/zsh
# Builds GaeaPluginHost.app: Developer ID, hardened runtime, not sandboxed, no LSFileQuarantineEnabled.
set -euo pipefail
HERE=${0:A:h}/..
DEVID="Developer ID Application: Dustin Nielson (CFZS6RXUCP)"
cd $HERE/Host && xcrun swift build -c release 2>&1 | tail -3
APP=$HERE/dist/GaeaPluginHost.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/GaeaPluginHost $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.xocialize.gaea.pluginspike</string>
  <key>CFBundleExecutable</key><string>GaeaPluginHost</string>
  <key>CFBundleName</key><string>Gaea Plugin Spike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
EOF
codesign -f -s $DEVID -o runtime --timestamp $APP
codesign -dv $APP 2>&1 | grep -E "Identifier|TeamIdentifier|flags"
