#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import contextlib
import json
import os
import pathlib
import subprocess
import sys
import tempfile

requested = os.environ.get("LUMA_CLEANUP_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-cleanup-sessions-")
required = [
    "mutationTrackedSeparately", "stoppingRetainsBusy", "partialCleanupRecorded",
    "remainingUntouched", "undoSheetAttached", "undoOnlyEligible", "undoRecorded",
    "allContentsPreserved", "monitoringContinued", "menuStayedVisible",
]
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([
            sys.argv[1], "--check-cleanup-sessions", str(output),
            "-luma.appearance", appearance, "-luma.menuBar", "YES",
        ], check=True, timeout=70)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report.get("realTrashInvoked") is False, report
        print(f"Passed {appearance}: in-flight Stop, durable partial session, actual Undo sheet, fixture restore, monitoring and menu continuity.")
PY
