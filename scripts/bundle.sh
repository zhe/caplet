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

# A real certificate lets macOS recognise rebuilds as the same app, so the Accessibility
# permission survives them. Ad-hoc signatures change with every build.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/"Apple Development: / { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "Built $APP (signed with \"$IDENTITY\")"
else
    codesign --force --sign - "$APP"
    echo "Built $APP (ad-hoc signed: re-add it under Accessibility after each rebuild;"
    echo "see \"Signing\" in README.md to avoid that)"
    if security find-identity -p codesigning 2>/dev/null | grep -q '"Apple Development: '; then
        echo
        echo "Note: an Apple Development certificate exists but macOS doesn't trust it yet,"
        echo "usually because Apple's intermediate certificate is missing. Install it with:"
        echo "  curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer && open AppleWWDRCAG3.cer"
        echo "then run this script again."
    fi
fi

if [[ "${1:-}" == "--install" ]]; then
    # TinyTiler handles SIGTERM like Quit, so it restores Caps Lock before being replaced.
    if pkill -x TinyTiler; then
        for _ in {1..25}; do pgrep -x TinyTiler >/dev/null || break; sleep 0.2; done
    fi
    rm -rf /Applications/TinyTiler.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/TinyTiler.app"
fi
