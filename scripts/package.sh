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
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Ad-hoc signature: required to run on Apple Silicon, free, but not notarized.
codesign --force --deep --sign - "$APP"

if [ "${1:-}" = "dmg" ]; then
    STAGE=build/dmg
    mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname Brisa -srcfolder "$STAGE" -ov -format UDZO "build/Brisa-$VERSION.dmg" >/dev/null
    rm -rf "$STAGE"
    echo "build/Brisa-$VERSION.dmg"
else
    echo "$APP"
fi
