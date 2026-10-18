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
    "warmStorageMetadata", "storageCoverageAndBytesMatch", "nestedNavigationAvailable",
    "noSelection", "warmHashesReused", "duplicateResultsMatch", "nativeEventInvalidation",
    "changedContentNotInGroup", "cacheClearFinished", "activityAndIgnoresPreserved",
    "clearForcesColdHashes", "monitoringContinued", "settingsPresented",
]
requested = os.environ.get("LUMA_INDEX_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-index-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-analysis-index", str(output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report.get("mutationInvoked") is False, report
        assert report.get("personalFoldersScanned") is False, report
        print(f"Passed {appearance}: warm metadata/hashes, native invalidation, navigation, cache clear and monitoring.")
PY
