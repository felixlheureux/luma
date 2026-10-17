#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="luma-lifecycle-") as directory:
    output = pathlib.Path(directory) / "report.json"
    subprocess.run([sys.argv[1], "--check-window-lifecycle", str(output), "-luma.menuBar", "YES"], check=True, timeout=25)
    if not output.exists():
        raise SystemExit("Luma exited before completing the window lifecycle check.")
    report = json.loads(output.read_text())
    assert report.get("windowClosed"), report
    assert report.get("monitoringContinued"), report
    assert report.get("windowReopened"), report
    assert report.get("menuBar", {}).get("visible"), report
    print("Passed: window closed, monitoring continued, menu item stayed visible, window reopened, explicit Quit exited.")
PY
