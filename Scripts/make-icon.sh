#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/LumaApp/Brand.swift Scripts/make-icon.swift -o .build/make-icon
.build/make-icon Resources
iconutil -c icns Resources/Luma.iconset -o Resources/Luma.icns
