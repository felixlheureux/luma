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

required = [
    "installedIconLoaded", "threeLeftoversTwoOwners", "directWithoutReview", "initialSelectionEmpty", "arrivalNotSelected", "wholeGroupSelected",
    "narrowWindow", "mixedGroupSelection", "mixedSelectsAll", "groupDeselectsAll", "navigationPreservesSelection",
    "liveMoveDetail", "elapsedClockPresent", "remainingResultsRetained",
    "oldScanTimeRetained", "savedRemainingObservations", "relaunchShowsSavedDuringRefresh", "selectionCleared",
    "nextActionWithoutRescan", "undoRefreshesResidue", "monitoringContinued",
]
requested = os.environ.get("LUMA_FEEDBACK_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-feedback-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark", "system"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-cleanup-feedback", str(output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=90)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report.get("realTrashInvoked") is False, report
        assert report.get("personalFoldersScanned") is False, report
        print(f"Passed {appearance}: local icons, owner grouping, live cleanup feedback, retained remaining results and direct residue actions.")
PY
