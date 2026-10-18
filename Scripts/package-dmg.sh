#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d dist/Luma.app ]; then bash Scripts/build-app.sh release; fi
mkdir -p .build
stage="$(mktemp -d .build/DMG.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto dist/Luma.app "$stage/Luma.app"
if [ ! -L "$stage/Applications" ]; then ln -s /Applications "$stage/Applications"; fi
cp LICENSE "$stage/License.txt"
cp Resources/Installer-ReadMe.txt "$stage/Read Me.txt"
luma_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Luma.app/Contents/Info.plist)"
luma_architecture="$(lipo -archs dist/Luma.app/Contents/MacOS/Luma)"
if [[ "$luma_architecture" == *" "* ]]; then luma_architecture="universal"; fi
hdiutil create -volname Luma -srcfolder "$stage" -format UDZO -ov "dist/Luma-$luma_version-$luma_architecture.dmg"
