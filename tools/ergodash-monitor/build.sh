#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/ErgoDash USB Monitor.app"
mkdir -p "$app/Contents/MacOS" build/module-cache
swiftc -O -module-cache-path build/module-cache -framework AppKit -framework IOKit \
    Report.swift main.swift -o "$app/Contents/MacOS/ErgoDash USB Monitor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ErgoDash USB Monitor</string>
  <key>CFBundleIdentifier</key><string>dev.andy.ergodash-usb-monitor</string>
  <key>CFBundleName</key><string>ErgoDash USB Monitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
"$app/Contents/MacOS/ErgoDash USB Monitor" --self-test
printf '%s\n' "Built $PWD/$app"
