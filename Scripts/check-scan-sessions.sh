#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import json
import contextlib
import os
import pathlib
import subprocess
import sys
import tempfile

required = [
    "expandedCacheUnits", "cacheGroups", "cacheUniqueBytes", "cacheAdjacentDataPreserved",
    "cacheNothingSelected", "cacheReviewTotalMatches", "cacheReviewPresented", "cacheSnapshotInvalidated",
    "metadataVisibleBeforeSizing", "previewCannotInspect", "navigationWhileScanning",
    "settingsWhileScanning", "windowClosedDuringScan", "windowReopenedDuringScan",
    "monitoringContinued", "menuStayedVisible", "stoppingUntilWorkerReturns",
    "providerScopeExcluded", "providerBytesNotCounted", "providerSelectionEmpty",
    "cancelledInventoryNotCommitted", "allSizesResolved", "partialReviewRejected",
    "deniedCoverageReported", "readableResultsRetained", "permissionRetrySameScope",
    "permissionRetrySucceeded", "newSnapshotTimestamp", "nothingSelected",
    "footprintSheetVisibleWhileScanning", "footprintInspectionTracked", "cancelledFootprintNotCommitted",
]
requested = os.environ.get("LUMA_SCAN_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-scan-sessions-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([
            sys.argv[1], "--check-scan-sessions", str(output),
            "-luma.appearance", appearance, "-luma.menuBar", "YES",
        ], check=True, timeout=100)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report.get("completedApplicationCount") == 30, report
        assert report.get("mainActorHeartbeatsDuringInventory", 0) > 0, report
        assert report.get("mutationInvoked") is False, report
        print(f"Passed {appearance}: scan cancellation, scoped retry, read-only previews, navigation/window/menu lifecycle; "
              f"6000-file inventory {report['inventorySeconds']:.3f}s, "
              f"maximum sampled main-actor delay {report['maxMainActorHeartbeatDelaySeconds']:.3f}s.")
PY
