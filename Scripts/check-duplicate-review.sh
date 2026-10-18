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

requested = os.environ.get("LUMA_DUPLICATE_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-duplicate-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-duplicate-review", str(output), "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        for key in ["nothingSelected", "comparisonLoaded", "unsupportedPreviewExplicit", "proposalPresented", "explicitSelection", "ordinaryReviewPresented", "changedKeeperRejected", "historyAndIgnoresPreserved", "monitoringContinued"]:
            assert report.get(key) is True, (key, report)
        assert report.get("mutationInvoked") is False and report.get("personalFoldersScanned") is False, report
        print(f"Passed {appearance}: comparison, proposal, keeper, ordinary review, changed-copy rejection and monitoring.")
PY
