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
required = ["noScanOnOpen", "noScanOnWarmOpen", "requestedScanWithoutPicker", "partialCoverage", "providerExcluded", "cloudMetadataVisible", "cloudCleanupRejected", "cloudBytesExcluded", "unreadablePartial", "nothingSelected",
            "selectionSurvivesNavigationAndFilters", "cachedHistory", "narrowWindow", "directTrashWithoutSheet",
            "unaffectedInventoryRetained", "undoWithoutSheet", "undoUpdatesObservation", "pendingScopeKeepsLabels", "failedScopeKeepsLabelsAndOutcome",
            "warmHierarchyAvailable", "persistenceSettles", "coreRoutes", "monitoringContinued", "windowFrameRestored", "oldVolumeDoesNotCancelNewScope",
            "volumeInvalidationPreservesResidues", "searchImmediateTyping", "searchKeyboardActivation", "searchEscape", "unrelatedDuplicateCompletionPreservesSelection"]
requested = os.environ.get("LUMA_STORAGE_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-storage-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark", "system"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-storage-browser", str(output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report["realTrashInvoked"] is False and report["personalFoldersScanned"] is False, report
        assert report["maxMainActorDelaySeconds"] < 1, report
        print(f"Passed {appearance}: idle cold/warm opening, requested scan, persistent selection, fixture Trash/Undo, scope retention, narrow layout and idle settling; "
              f"{report['nodes']} nodes; first {report['firstResultsSeconds']:.3f}s, warm {report['warmOpenSeconds']:.3f}s, complete {report['discoverySeconds']:.3f}s; main delay {report['maxMainActorDelaySeconds']:.3f}s; Trash {report['trashSeconds']:.3f}s, Undo {report['undoSeconds']:.3f}s.")
PY
