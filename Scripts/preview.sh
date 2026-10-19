#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash Scripts/make-icon.sh
bash Scripts/build-app.sh debug
mkdir -p Documentation/Screenshots
# Do not accept an old image when a launch fails to render its main window.
rm -f Documentation/Screenshots/{overview,overview-dark,system-dark,activity-dark,menu-light,menu-dark}.png
# Launch as a foreground app; direct CLI launches may never create the main window.
python3 - <<'PY_RENDER'
from pathlib import Path
import subprocess
root = Path.cwd()
bundle = root / "dist/Luma.app"
for name, appearance, page, menu in [
    ("overview.png", "light", None, False),
    ("overview-dark.png", "dark", None, False),
    ("system-dark.png", "dark", "System", False),
    ("activity-dark.png", "dark", "Activity", False),
    ("menu-light.png", "light", None, True),
    ("menu-dark.png", "dark", None, True),
]:
    args = ["--check-preview", "--snapshot-menu" if menu else "--snapshot",
            str(root / "Documentation/Screenshots" / name), "-luma.appearance", appearance]
    if page:
        args += ["--page", page]
    subprocess.run(["/usr/bin/open", "-W", "-n", str(bundle), "--args", *args], check=True, timeout=30)
PY_RENDER

python3 - <<'PY_CHECK'
from pathlib import Path
import struct
for name in ["overview.png", "overview-dark.png", "system-dark.png", "activity-dark.png"]:
    data = (Path("Documentation/Screenshots") / name).read_bytes()
    width, height = struct.unpack(">II", data[16:24])
    assert width >= 600 and height >= 400, (name, width, height)
print("Main-window preview dimensions verified")
PY_CHECK
