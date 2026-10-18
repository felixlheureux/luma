#!/bin/bash
# Verify the mounted payload, not just the image container. Never launch the app.
set -euo pipefail
cd "$(dirname "$0")/.."
image="${1:?Usage: bash Scripts/verify-dmg.sh path/to/Luma.dmg}"
hdiutil verify "$image"
mount="$(mktemp -d "${TMPDIR:-/tmp}/luma-installer.XXXXXX")"
attached=false
cleanup() {
    if [ "$attached" = true ]; then hdiutil detach "$mount"; fi
    rmdir "$mount"
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$image"
attached=true
python3 - "$mount" <<'PY'
import hashlib
from pathlib import Path
import plistlib
import sys

mount = Path(sys.argv[1])
app = mount / "Luma.app"
with (app / "Contents/Info.plist").open("rb") as source:
    actual = plistlib.load(source)
with Path("Resources/Info.plist").open("rb") as source:
    expected = plistlib.load(source)
assert actual == expected, "Packaged app metadata differs from source"
assert (mount / "Applications").is_symlink(), "Missing Applications shortcut"
assert (mount / "Applications").readlink() == Path("/Applications")
for packaged, source in [
    (mount / "Read Me.txt", Path("Resources/Installer-ReadMe.txt")),
    (mount / "License.txt", Path("LICENSE")),
    (app / "Contents/Resources/LICENSE", Path("LICENSE")),
    (app / "Contents/Resources/Luma.icns", Path("Resources/Luma.icns")),
    (app / "Contents/MacOS/Luma", Path("dist/Luma.app/Contents/MacOS/Luma")),
]:
    assert packaged.is_file() and source.is_file(), f"Missing payload: {packaged.name}"
    assert hashlib.sha256(packaged.read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest(), f"Stale payload: {packaged.name}"
print(f'Passed: mounted Luma {actual["CFBundleShortVersionString"]} build {actual["CFBundleVersion"]}, executable, icon, license and installer text match the build.')
PY
codesign --verify --deep --strict "$mount/Luma.app"
