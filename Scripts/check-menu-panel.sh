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
requested = os.environ.get("LUMA_MENU_QA_OUTPUT_DIR")
with (contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-menu-")) as directory:
    pathlib.Path(directory).mkdir(parents=True, exist_ok=True)
    output = pathlib.Path(directory) / "panel.json"
    output.unlink(missing_ok=True)
    subprocess.run([sys.argv[1], "--check-menu-panel", str(output)], check=True, timeout=60)
    report = json.loads(output.read_text())
    assert "error" not in report, report
    for appearance in ["light", "dark", "system"]:
        for check in ["OpeningKey", "NoMainFlash", "Arrowless", "FitsScreen", "NativeLiquidGlass", "NoMenuBarGap", "InteriorClickKeepsAppearance", "FirstClickMaintenance", "FirstClickOpenRetainsPage", "EscapeDismisses"]:
            assert report.get(appearance + check) is True, report
    for key in ["hiddenMainSkipsProcesses", "navigateReopensAtRequestedPage", "menuOnlyMonitoringContinues", "outsideClickDismisses", "dismissalObserversRemoved", "iconClickOpens", "iconClickCloses", "preferenceDisablesPanelAndIcon", "preferenceRemovesObservers", "settingsOnlyBeforeDockReopen", "dockReopensWithSettingsVisible"]:
        assert report.get(key) is True, report
    assert report["mutationInvoked"] is False, report
    print("Passed: flat key panel, first-click footer actions, Escape/outside dismissal, screen clamping, closed-window navigation and lightweight menu monitoring in Light/Dark/System.")
    print(f"Available real displays: {report['displayCount']}; secondary/short-screen bounds also injected.")
PY
