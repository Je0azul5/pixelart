#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/JeXelart.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/JeXelart" "$APP/Contents/MacOS/JeXelart"
cp packaging/Info.plist "$APP/Contents/Info.plist"
swift scripts/create-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/JeXelart.iconset" -o "$APP/Contents/Resources/JeXelart.icns"
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$PWD/dist/JeXelart-macOS.zip"
printf 'Aplicación: %s\nZIP: %s\n' "$APP" "$PWD/dist/JeXelart-macOS.zip"
