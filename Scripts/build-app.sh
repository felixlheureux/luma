#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration"
binary_directory="$(swift build -c "$configuration" --show-bin-path)"
bundle="dist/Luma.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_directory/Luma" "$bundle/Contents/MacOS/Luma"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
if [ -f Resources/Luma.icns ]; then cp Resources/Luma.icns "$bundle/Contents/Resources/Luma.icns"; fi
cp LICENSE "$bundle/Contents/Resources/LICENSE"
codesign --force --sign - "$bundle"
printf 'Built %s\n' "$PWD/$bundle"
