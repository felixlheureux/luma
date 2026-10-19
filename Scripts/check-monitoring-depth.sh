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

requested = os.environ.get("LUMA_MONITORING_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-monitoring-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark", "system"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        output.unlink(missing_ok=True)
        args = [sys.argv[1], "--check-monitoring-depth", str(output), "-luma.appearance", appearance, "-luma.menuBar", "YES"]
        bundle = pathlib.Path(sys.argv[1]).resolve().parents[2]
        command = ["/usr/bin/open", "-W", "-n", str(bundle), "--args", *args[1:]] if bundle.suffix == ".app" else args
        subprocess.run(command, check=True, timeout=90)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        for key in ["singleInterfaceRate", "supportedBatteryFields", "desktopExplicit", "unsupportedFieldsUnavailable", "menuFitsScreen", "menuWithoutMainWindow", "memoryPressureDistinct", "detailFieldsAndTime", "detailCacheReused", "detailRequestsCoalesced", "lightweightDuringDetails", "detailFailurePreservesReadings", "monitorContinuesAfterDetailFailure", "partialDetailsExplained", "actualLightweightIdentityAvailable", "actualLumaMatchesPowerReport", "staleSourceDetailsDiscarded"]:
            assert report.get(key) is True, (key, report)
        assert report["mutationInvoked"] is False and report["activeNetworkTestInvoked"] is False and report["personalFoldersScanned"] is False
        assert report["actualNetworkProviderAvailable"] is True, report
        assert report["extendedP95Seconds"] < 0.2, report
        print(f"Passed {appearance}: rates, battery availability, menu-only monitoring; core median {report['coreMedianSeconds']*1000:.2f} ms, extended median/p95 {report['extendedMedianSeconds']*1000:.2f}/{report['extendedP95Seconds']*1000:.2f} ms.")
PY
