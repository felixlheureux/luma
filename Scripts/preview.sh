#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/make-icon.sh
bash Scripts/build-app.sh debug
mkdir -p Documentation/Screenshots
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot "$PWD/Documentation/Screenshots/overview.png" -luma.appearance light
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot "$PWD/Documentation/Screenshots/overview-dark.png" -luma.appearance dark
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot "$PWD/Documentation/Screenshots/system-dark.png" --page System -luma.appearance dark
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot "$PWD/Documentation/Screenshots/activity-dark.png" --page Activity -luma.appearance dark
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot-menu "$PWD/Documentation/Screenshots/menu-light.png" -luma.appearance light
dist/Luma.app/Contents/MacOS/Luma --check-preview --snapshot-menu "$PWD/Documentation/Screenshots/menu-dark.png" -luma.appearance dark

python3 - <<'PY_CHECK'
from pathlib import Path
import struct
for name in ["overview.png", "overview-dark.png", "system-dark.png", "activity-dark.png"]:
    data = (Path("Documentation/Screenshots") / name).read_bytes()
    width, height = struct.unpack(">II", data[16:24])
    assert width >= 600 and height >= 400, (name, width, height)
print("Main-window preview dimensions verified")
PY_CHECK
