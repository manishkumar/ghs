#!/usr/bin/env bash
# Assembles ghs.app from the SPM binary. LSUIElement keeps it out of the Dock
# and out of the app switcher — it exists only in the status bar.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/ghs.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ghs"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ghs"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ghs</string>
    <key>CFBundleDisplayName</key><string>GitHub Review Queue</string>
    <key>CFBundleIdentifier</key><string>com.manishkumar.ghs</string>
    <key>CFBundleExecutable</key><string>ghs</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <!-- Status bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so the Keychain item stays bound to a stable identity across
# rebuilds; replace with a Developer ID signature to distribute.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
