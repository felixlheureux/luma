#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import json
import os
import pathlib
import subprocess
import sys
import struct
import time
import tempfile

folder = pathlib.Path(os.environ.get("LUMA_OVERVIEW_QA_OUTPUT_DIR") or tempfile.mkdtemp(prefix="luma-overview-input-"))
folder.mkdir(parents=True, exist_ok=True)
for saved in [False, True]:
    output = folder / ("old-storage-page.json" if saved else "fresh.json")
    output.unlink(missing_ok=True)
    args = [sys.argv[1], "--check-overview-input", str(output), "--overview-fixture-root", str(pathlib.Path.cwd() / ".build" / "Fixtures"), "-luma.menuBar", "YES"]
    if saved:
        args += ["-luma.lastCorePage", "Storage"]
    started = time.time()
    bundle = pathlib.Path(sys.argv[1]).resolve().parents[2]
    # LaunchServices supplies the normal foreground launch context for pointer QA.
    command = ["/usr/bin/open", "-W", "-n", str(bundle), "--args", *args[1:]] if bundle.suffix == ".app" else args
    subprocess.run(command, check=True, timeout=90)
    result = json.loads(output.read_text())
    assert "error" not in result, result
    assert result["mutationInvoked"] is False and result["personalFoldersScanned"] is False, result
    assert all(value is True for key, value in result.items() if key not in ["mutationInvoked", "personalFoldersScanned"]), result
    suffixes = [f"{appearance}-{view}" for appearance in ["light", "dark", "system"] for view in ["residues", "footer", "overview"]] + ["collecting", "unavailable-stale"]
    for suffix in suffixes:
        capture = pathlib.Path(str(output) + "-" + suffix + ".png")
        assert capture.stat().st_mtime >= started, capture
        width, height = struct.unpack(">II", capture.read_bytes()[16:24])
        assert width >= 600 and height >= 400, (capture, width, height)
    print(f"Passed native Overview/input checks ({'old Storage preference' if saved else 'default launch'}).")
print(f"Reports and captures: {folder}")
PY
