#!/usr/bin/env python3
"""Reject inconsistent release metadata before building or publishing."""
import argparse
from pathlib import Path
import plistlib
import re


def validate_version(root: Path, tag: str = "") -> str:
    with (root / "Resources/Info.plist").open("rb") as source:
        version = plistlib.load(source)["CFBundleShortVersionString"]
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("App version must have three numeric components, such as 0.1.3.")
    if tag and tag != f"v{version}":
        raise ValueError(f"Release tag {tag!r} does not match app version v{version}.")
    header = (root / "Resources/Installer-ReadMe.txt").read_text().splitlines()[0]
    if header != f"Luma {version} — Development Build":
        raise ValueError("Installer README version does not match Resources/Info.plist.")
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", default="", help="Existing release tag; omit for a build-only run.")
    args = parser.parse_args()
    try:
        print(validate_version(Path(__file__).resolve().parent.parent, args.tag))
    except (ValueError, OSError, KeyError, IndexError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Release metadata rejected: {error}\n")
