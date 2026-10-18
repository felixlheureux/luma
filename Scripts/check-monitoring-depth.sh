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
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-monitoring-depth", str(output), "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        for key in ["singleInterfaceRate", "supportedBatteryFields", "desktopExplicit", "unsupportedFieldsUnavailable", "menuFitsScreen", "menuWithoutMainWindow", "memoryPressureDistinct"]:
            assert report.get(key) is True, (key, report)
        assert report["mutationInvoked"] is False and report["activeNetworkTestInvoked"] is False and report["personalFoldersScanned"] is False
        assert report["actualNetworkProviderAvailable"] is True, report
        assert report["extendedP95Seconds"] < 0.2, report
        print(f"Passed {appearance}: rates, battery availability, menu-only monitoring; core median {report['coreMedianSeconds']*1000:.2f} ms, extended median/p95 {report['extendedMedianSeconds']*1000:.2f}/{report['extendedP95Seconds']*1000:.2f} ms.")
PY
