#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Pixelart.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Pixelart" "$APP/Contents/MacOS/Pixelart"
cp packaging/Info.plist "$APP/Contents/Info.plist"
swift scripts/create-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/Pixelart.iconset" -o "$APP/Contents/Resources/Pixelart.icns"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/Pixelart-macOS.zip"
printf 'Aplicación: %s\nZIP: %s\n' "$APP" "$PWD/dist/Pixelart-macOS.zip"
