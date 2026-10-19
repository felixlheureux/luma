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
required = ["nativeSheet", "nothingSelected", "partialRetainsReadable", "fourCategories", "deniedIsUnknown",
            "absentIsDistinct", "namedMapping", "separateBundleChoice", "reviewMatchesTotals", "retryComplete", "monitoringContinued", "mutationInvalidatesFootprint", "resetNativeSheet", "resetStartsEmpty", "resetKeyboardFocus", "resetGroups", "resetReview", "mutationInvalidatesLeftovers"]
requested = os.environ.get("LUMA_FOOTPRINT_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-footprint-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark", "system"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-application-footprint", str(output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report["mutationInvoked"] is False, report
        direct_output = pathlib.Path(directory) / f"{appearance}-direct.json"
        subprocess.run([sys.argv[1], "--check-direct-uninstall", str(direct_output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        direct = json.loads(direct_output.read_text())
        assert "error" not in direct, direct
        checks = ["partialInventoryRetainsUnavailableRow", "sizeFailureDoesNotKeepDeletedRows", "metadataMergeKeepsIcon", "vendorInventoryAndIcon", "twoComponentEligible", "restoredIcon", "bundleOnlyRetainsOptionalData", "automaticProgressiveInventory", "noScanOrDetailsRequired", "narrowWindow", "windowSizeRestored",
                  "unrelatedScanAllowsUninstall", "unrelatedQueuedScanPreserved", "promptFeedback", "bundleRetainedUntilConfirmedMove",
                  "navigationKeepsMutation", "completedWithoutSheets", "onlyConfirmedBundleRemoved",
                  "retainedDocuments", "selectionPreserved", "directUndoWithoutSheet", "restoredRowReturns",
                  "staleInventoryCannotHideRestore", "restoredOutcome", "quitWaitsForDrain", "quitDrainsBeforeReply", "journalLoadingDisablesAction",
                  "journalErrorExplainsAction", "blockedRowRemainsInline", "lateKeeperCannotReopenOrSelect"]
        assert all(direct.get(key) is True for key in checks), direct
        assert direct["realTrashInvoked"] is False, direct
        print(f"Passed {appearance} direct uninstall/Undo with generated data; {direct['seconds']:.3f}s.")
        print(f"Passed {appearance}: native footprint groups, named evidence, partial/absent reads, explicit selection, review totals, reset review, keyboard focus and retry.")
PY
