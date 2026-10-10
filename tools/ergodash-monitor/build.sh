#!/bin/sh
set -eu
cd "$(dirname "$0")"
app="build/ErgoDash USB Monitor.app"
mkdir -p "$app/Contents/MacOS" build/module-cache
arch=$(uname -m)
swiftc -O -target "$arch-apple-macos14.0" -module-cache-path build/module-cache \
    -framework AppKit -framework IOKit -framework SwiftUI -framework WidgetKit \
    Report.swift WidgetSnapshot.swift BatteryWidgetView.swift BackgroundService.swift USBCollector.swift main.swift \
    -o "$app/Contents/MacOS/ErgoDash USB Monitor"
extension="$app/Contents/PlugIns/ErgoDashWidget.appex"
mkdir -p "$extension/Contents/MacOS"
# Initialize the macOS extension context before Swift's Widget.main runs.
# Without this entry point the bundle registers, but crashes on gallery queries.
swiftc -O -parse-as-library -application-extension -target "$arch-apple-macos14.0" \
    -module-cache-path build/module-cache -framework SwiftUI -framework WidgetKit \
    -Xlinker -e -Xlinker _NSExtensionMain \
    Report.swift WidgetSnapshot.swift BatteryWidgetView.swift Widget.swift \
    -o "$extension/Contents/MacOS/ErgoDashWidget"
cat > "$extension/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ErgoDashWidget</string>
  <key>CFBundleIdentifier</key><string>dev.andy.ergodash-usb-monitor.widget</string>
  <key>CFBundleName</key><string>ErgoDash Batteries</string>
  <key>CFBundleDisplayName</key><string>ErgoDash Batteries</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>3.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict></plist>
PLIST
cat > build/widget-entitlements.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements build/widget-entitlements.plist "$extension"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>ErgoDash USB Monitor</string>
  <key>CFBundleIdentifier</key><string>dev.andy.ergodash-usb-monitor</string>
  <key>CFBundleName</key><string>ErgoDash USB Monitor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>3.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>ErgoDash Monitor</string>
    <key>CFBundleURLSchemes</key><array><string>ergodash-monitor</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/ErgoDash USB Monitor" --self-test
printf '%s\n' "Built $PWD/$app"
