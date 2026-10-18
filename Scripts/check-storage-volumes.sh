#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-dist/Luma.app/Contents/MacOS/Luma}" <<'PY'
import contextlib
import json
import os
import pathlib
import subprocess
import struct
import sys
import tempfile
import time

requested = os.environ.get("LUMA_VOLUME_QA_OUTPUT_DIR")
context = contextlib.nullcontext(requested) if requested else tempfile.TemporaryDirectory(prefix="luma-volume-reports-")
with context as report_directory, tempfile.TemporaryDirectory(prefix="luma-volume-fixture-", dir="/private/tmp") as fixture_directory:
    report_directory = pathlib.Path(report_directory)
    report_directory.mkdir(parents=True, exist_ok=True)
    fixture = pathlib.Path(fixture_directory)
    seed = fixture / "seed"
    (seed / "Nested").mkdir(parents=True)
    (seed / "Nested" / "notes.txt").write_text("Disposable volume fixture.\n")
    (seed / "root.txt").write_text("Local fixture, never personal data.\n")
    image = fixture / "fixture.dmg"
    mount = fixture / "mount"
    mount.mkdir()
    subprocess.run(["hdiutil", "create", "-srcfolder", str(seed), "-fs", "APFS", "-size", "128m", "-format", "UDRO", "-volname", "LumaVolumeQA", str(image)], check=True, stdout=subprocess.DEVNULL)
    for appearance in ["light", "dark"]:
        output = report_directory / f"{appearance}.json"
        ready = pathlib.Path(str(output) + ".ready")
        ready.unlink(missing_ok=True)
        output.unlink(missing_ok=True)
        attached = False
        process = None
        try:
            subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)], check=True, stdout=subprocess.DEVNULL)
            attached = True
            process = subprocess.Popen([sys.argv[1], "--check-storage-volumes", str(output), "-luma.appearance", appearance, "-luma.menuBar", "YES", "-ApplePersistenceIgnoreState", "YES"], env={**os.environ, "LUMA_VOLUME_QA_ROOT": str(mount)})
            deadline = time.monotonic() + 45
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            assert ready.exists(), output.read_text() if output.exists() else "Fixture analysis did not become ready"
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
            attached = False
            process.wait(timeout=40)
            report = json.loads(output.read_text())
            assert "error" not in report, report
            for key in ["readOnlyVolume", "scopeVisible", "nothingSelected", "listNavigationAvailable", "coreReviewRejected", "appReviewRejected", "unmountInvalidated", "monitoringContinued"]:
                assert report.get(key) is True, (key, report)
            assert report["logicalBytes"] >= 61, report
            assert report["mutationInvoked"] is False and report["personalFoldersScanned"] is False, report
            for suffix in ["-analysis.png", "-unmounted.png"]:
                capture = pathlib.Path(str(output) + suffix).read_bytes()
                width, height = struct.unpack(">II", capture[16:24])
                assert width > 800 and height > 500, (width, height)
            print(f"Passed {appearance}: real read-only volume, navigation, core/app rejection, unmount invalidation and monitoring.")
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
            if attached:
                subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
PY
