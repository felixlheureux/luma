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
required = ["partialRoot", "providerExcluded", "unreadablePartial", "nothingSelected",
            "remainderMatchesList", "reviewPresented", "threeLevelsAndSelectionCleared",
            "cachedNavigation", "breadcrumbBack", "emptyComplete", "staleReviewRejected",
            "monitoringContinued"]
requested = os.environ.get("LUMA_STORAGE_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-storage-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    for appearance in ["light", "dark"]:
        output = pathlib.Path(directory) / f"{appearance}.json"
        subprocess.run([sys.argv[1], "--check-storage-browser", str(output),
                        "-luma.appearance", appearance, "-luma.menuBar", "YES"], check=True, timeout=60)
        report = json.loads(output.read_text())
        assert "error" not in report, report
        assert all(report.get(key) is True for key in required), report
        assert report["mutationInvoked"] is False, report
        print(f"Passed {appearance}: hierarchy, cached navigation, map coverage, partial/empty states, review and stale rejection; "
              f"{report['nodes']} nodes in {report['indexSeconds']:.3f}s.")
PY
