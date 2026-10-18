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

requested = os.environ.get("LUMA_UX_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-native-ux-")
with context as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    output = pathlib.Path(directory) / "native-ux.json"
    subprocess.run([sys.argv[1], "--check-native-ux", str(output), "-luma.menuBar", "YES", "-luma.appearance", "system"], check=True, timeout=60)
    report = json.loads(output.read_text())
    assert "error" not in report, report
    for key in ["monitoringContinued", "menuVisible", "windowVisible", "nothingSelected"]:
        assert report.get(key) is True, report
    assert report.get("mutationInvoked") is False, report
    samples = report["pageSamples"]
    expected = {(appearance, increased_contrast) for appearance in ["light", "dark", "system"] for increased_contrast in [False, True]}
    assert {(sample["appearance"], sample["increasedContrast"]) for sample in samples} == expected
    for appearance, increased_contrast in expected:
        pages = [sample["page"] for sample in samples if sample["appearance"] == appearance and sample["increasedContrast"] == increased_contrast]
        assert len(pages) == report["pageCount"] == len(set(pages)) and len(pages) > 0
        capture = pathlib.Path(str(output) + f'-{appearance}-{"contrast" if increased_contrast else "standard"}.png')
        assert capture.stat().st_size > 0, capture
    worst = max(sample["layoutSecondsIncludingYield"] for sample in samples)
    print(f"Passed: {len(samples)} page/layout samples across three appearances and increased contrast appearances; monitoring/menu continued.")
    print(f"Longest layout sample including 20 ms yield: {worst:.3f}s (not a frame trace).")
    print("Keyboard/VoiceOver and full composited appearance review remain manual release gates.")
PY
