#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
swift scripts/create-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/build/Vimstride.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Vimstride" "$app/Contents/MacOS/Vimstride"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Click.wav "$app/Contents/Resources/Click.wav"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
