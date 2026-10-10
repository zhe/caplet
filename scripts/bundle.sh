#!/usr/bin/env bash
# Builds TinyTiler.app in ./build. Running it as an .app (instead of `swift run`) makes
# macOS attach the Accessibility permission to TinyTiler rather than to your terminal.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/TinyTiler.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/TinyTiler"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TinyTiler"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.tinytiler.TinyTiler</string>
    <key>CFBundleName</key>
    <string>TinyTiler</string>
    <key>CFBundleExecutable</key>
    <string>TinyTiler</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
