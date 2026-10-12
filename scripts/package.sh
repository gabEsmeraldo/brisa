#!/bin/bash
# Builds a universal Brisa.app and an unsigned (ad-hoc) DMG into build/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
[ -z "$VERSION" ] && VERSION=0.0.0
APP=build/Brisa.app

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Brisa"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Brisa"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: required to run on Apple Silicon, free, but not notarized.
codesign --force --deep --sign - "$APP"

if [ "${1:-}" = "dmg" ]; then
    DMG="build/Brisa-$VERSION.dmg"
    swift scripts/make-dmg-background.swift .
    tiffutil -cathidpicheck build/bg.png build/bg@2x.png -out build/dmg-background.tiff >/dev/null
    STAGE=build/dmg && mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/"
    # Styled installer window: breeze background, app on the left, Applications on the right.
    create-dmg \
        --volname Brisa \
        --volicon Resources/AppIcon.icns \
        --background build/dmg-background.tiff \
        --window-pos 200 160 \
        --window-size 660 400 \
        --icon-size 112 \
        --text-size 13 \
        --icon Brisa.app 180 190 \
        --hide-extension Brisa.app \
        --app-drop-link 480 190 \
        --no-internet-enable \
        "$DMG" "$STAGE" >/dev/null
    rm -rf "$STAGE"
    echo "$DMG"
else
    echo "$APP"
fi
