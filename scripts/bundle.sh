#!/usr/bin/env bash
# Builds Caplet.app in ./build. Running it as an .app (instead of `swift run`) makes
# macOS attach the Accessibility permission to Caplet rather than to your terminal.
#
# --release VERSION builds a universal (Apple silicon + Intel) app stamped with VERSION and
# packs it as build/Caplet-VERSION.zip, ready to attach to a GitHub release.
set -euo pipefail

usage() { echo "usage: $0 [--install] [--zip] [--release VERSION]" >&2; exit 64; }

INSTALL=0
ZIP=0
ZIPFILE="build/Caplet.zip"
VERSION="0.0.0"   # local builds; releases pass their own
ARCHS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) INSTALL=1 ;;
        --zip) ZIP=1 ;;
        --release)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
                || { echo "--release needs a version like 1.2.3" >&2; usage; }
            VERSION="$2"; ZIP=1; ZIPFILE="build/Caplet-$2.zip"
            ARCHS=(--arch arm64 --arch x86_64)
            shift ;;
        *) usage ;;
    esac
    shift
done

cd "$(dirname "$0")/.."
APP="build/Caplet.app"

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Caplet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Caplet"
# Copied straight into Contents/Resources, where Bundle.main finds them. SwiftPM resources
# (Bundle.module) would look in the .app's root, which codesign doesn't allow.
cp Resources/AppIcon.icns Resources/MenuBarIcon.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>net.zhezhang.Caplet</string>
    <key>CFBundleName</key>
    <string>Caplet</string>
    <key>CFBundleExecutable</key>
    <string>Caplet</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
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
elif [[ ${#ARCHS[@]} -gt 0 ]]; then
    # Users would have to re-grant Accessibility after every update of an ad-hoc release.
    echo "--release needs a signing certificate; see \"Signing\" in README.md" >&2
    exit 1
else
    codesign --force --sign - "$APP"
    echo "Built $APP (ad-hoc signed: re-add it under Accessibility after each rebuild;"
    echo "see \"Signing\" in README.md to avoid that)"
    if security find-identity -p codesigning 2>/dev/null | grep -q '"Apple Development: '; then
        echo
        echo "Note: an Apple Development certificate exists but macOS doesn't trust it yet,"
        echo "usually because Apple's intermediate certificate is missing. Install it with:"
        echo "  curl -fsSL -o /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer && open /tmp/AppleWWDRCAG3.cer"
        echo "then run this script again."
    fi
fi

if [[ "$ZIP" == 1 ]]; then
    # ditto keeps the code signature intact; Finder's Compress does too, plain `zip` may not.
    rm -f "$ZIPFILE"
    ditto -c -k --keepParent "$APP" "$ZIPFILE"
    echo "Packed $ZIPFILE (copy it to another Mac; see \"Other Macs\" in README.md)"
fi

if [[ "$INSTALL" == 1 ]]; then
    # Caplet handles SIGTERM like Quit, so it restores Caps Lock before being replaced.
    if pkill -x Caplet; then
        for _ in {1..25}; do pgrep -x Caplet >/dev/null || break; sleep 0.2; done
    fi
    rm -rf /Applications/Caplet.app
    cp -R "$APP" /Applications/
    echo "Installed /Applications/Caplet.app"
fi
