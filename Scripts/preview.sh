#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift Scripts/make-icon.swift Resources
iconutil -c icns Resources/Luma.iconset -o Resources/Luma.icns
bash Scripts/build-app.sh debug
mkdir -p Documentation/Screenshots
dist/Luma.app/Contents/MacOS/Luma --snapshot "$PWD/Documentation/Screenshots/overview.png" -luma.appearance light
dist/Luma.app/Contents/MacOS/Luma --snapshot "$PWD/Documentation/Screenshots/overview-dark.png" -luma.appearance dark
dist/Luma.app/Contents/MacOS/Luma --snapshot "$PWD/Documentation/Screenshots/system-dark.png" --page System -luma.appearance dark
