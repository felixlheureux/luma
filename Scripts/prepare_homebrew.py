"""Prepare a reviewable cask from verified, already-published Luma assets.

Never publishes, commits, pushes, executes the downloaded app, or changes macOS
security settings. All output is withheld until release and payload checks pass.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

REPOSITORY = "felixlheureux/luma"
TOKEN = "luma"
BASE_URL = f"https://github.com/{REPOSITORY}/releases/download"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120).stdout


def release_assets(release, tag):
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Expected an exact release tag such as v0.2.0")
    if release.get("tag_name") != tag or release.get("draft") is not False or not release.get("published_at"):
        raise ValueError("The exact tag must have a published, non-draft GitHub release")
    version = tag[1:]
    expected = [f"Luma-{version}-arm64.dmg", "SHA256SUMS"]
    assets = {}
    for name in expected:
        matches = [asset for asset in release.get("assets", []) if asset.get("name") == name]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one published asset: {name}")
        asset = matches[0]
        if asset.get("state") != "uploaded" or asset.get("browser_download_url") != f"{BASE_URL}/{tag}/{name}":
            raise ValueError(f"Unexpected asset state or URL: {name}")
        limit = 1_048_576 if name == "SHA256SUMS" else 1_073_741_824
        if not isinstance(asset.get("size"), int) or not 0 < asset["size"] <= limit:
            raise ValueError(f"Invalid published asset size: {name}")
        assets[name] = asset
    return version, assets


def verify_downloads(directory, version, assets):
    name = f"Luma-{version}-arm64.dmg"
    digests = {}
    for filename, asset in assets.items():
        path = directory / filename
        if not path.is_file() or path.is_symlink() or path.stat().st_size != asset["size"]:
            raise ValueError(f"Missing or size-mismatched download: {filename}")
        with path.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        if asset.get("digest") and asset["digest"] != f"sha256:{digest}":
            raise ValueError(f"GitHub asset digest mismatch: {filename}")
        digests[filename] = digest
    manifest = (directory / "SHA256SUMS").read_text(encoding="utf-8")
    lines = [line for line in manifest.splitlines() if line.strip()]
    # This distribution currently publishes one Apple Silicon installer. Refuse
    # ambiguous/new layouts until their multi-artifact policy is reviewed.
    if len(lines) != 1:
        raise ValueError("SHA256SUMS must identify exactly one installer")
    match = re.fullmatch(r"([a-fA-F0-9]{64}) [ *](Luma-[0-9.]+-arm64\.dmg)", lines[0])
    if not match or match[2] != name or match[1].lower() != digests[name]:
        raise ValueError("Published installer checksum/name does not match the downloaded DMG")
    return digests[name]


def validate_payload(info, architecture, build_output, version):
    expected = {"CFBundleIdentifier": "app.luma.mac", "CFBundleShortVersionString": version,
                "CFBundleExecutable": "Luma", "CFBundlePackageType": "APPL"}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("Published app identity/version does not match the release")
    if architecture.strip() != "arm64":
        raise ValueError("Only a verified arm64 executable is supported")
    # Both plist and Mach-O deployment target must agree with the cask. New
    # releases/minor deployment requirements need an explicit policy update.
    if info.get("LSMinimumSystemVersion") not in ["26", "26.0", "26.0.0"]:
        raise ValueError("Expected macOS 26.0 in the published app metadata")
    platforms = re.findall(r"^\s*platform\s+(\S+)\s*$", build_output, re.MULTILINE)
    minimums = re.findall(r"^\s*minos\s+(\S+)\s*$", build_output, re.MULTILINE)
    if platforms != ["MACOS"] or minimums not in [["26.0"], ["26.0.0"]]:
        raise ValueError("Mach-O platform/deployment target does not match macOS 26.0")
    return "tahoe"


def inspect_image(image, version):
    run("/usr/bin/hdiutil", "verify", str(image))
    with tempfile.TemporaryDirectory(prefix="luma-cask-mount-") as mount_dir:
        attached = False
        try:
            run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount_dir, str(image))
            attached = True
            mount = Path(mount_dir)
            app = mount / "Luma.app"
            if app.is_symlink() or not app.is_dir() or any(mount.glob("*.pkg")):
                raise ValueError("Expected a plain Luma.app installer without packages")
            if (app / "Contents/Info.plist").is_symlink():
                raise ValueError("App metadata must not be a symlink")
            with (app / "Contents/Info.plist").open("rb") as source:
                info = plistlib.load(source)
            executable = app / "Contents/MacOS/Luma"
            if executable.is_symlink():
                raise ValueError("App executable must not be a symlink")
            icon_name = info.get("CFBundleIconFile")
            if icon_name not in ["Luma", "Luma.icns"] or not (app / "Contents/Resources/Luma.icns").is_file():
                raise ValueError("Published app is missing its declared Luma icon")
            macos = validate_payload(info, run("/usr/bin/lipo", "-archs", str(executable)),
                                     run("/usr/bin/xcrun", "vtool", "-show-build", str(executable)), version)
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
            return macos
        finally:
            if attached or os.path.ismount(mount_dir):
                run("/usr/bin/hdiutil", "detach", mount_dir)


def render_cask(version, checksum, macos):
    # Version/checksum are validated before interpolation. No Ruby is taken from
    # release descriptions, asset labels, URLs, filenames or other remote text.
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or not re.fullmatch(r"[a-f0-9]{64}", checksum) or macos != "tahoe":
        raise ValueError("Invalid cask render inputs")
    return f'''cask "luma" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/felixlheureux/luma/releases/download/v#{{version}}/Luma-#{{version}}-arm64.dmg"
  name "Luma"
  desc "Local-first storage review and maintenance"
  homepage "https://github.com/felixlheureux/luma"

  livecheck do
    skip "Development prereleases are reviewed manually"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Luma.app"

  uninstall quit: "app.luma.mac"

  caveats do
    <<~EOS
      Development build. macOS may block first launch.
      Homebrew preserves quarantine and does not change system security settings.
    EOS
  end
end
'''


def prepare(tag, output, inspect=inspect_image, command=run):
    # Validate syntax before putting the tag into an API route or download args.
    if not re.fullmatch(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", tag):
        raise ValueError("Expected an exact version tag such as v0.2.0")
    api_path = f"repos/{REPOSITORY}/releases/tags/{tag}"
    release = json.loads(command("gh", "api", api_path))
    version, assets = release_assets(release, tag)
    with tempfile.TemporaryDirectory(prefix="luma-cask-release-") as temporary:
        directory = Path(temporary)
        command("gh", "release", "download", tag, "--repo", REPOSITORY, "--pattern", f"Luma-{version}-arm64.dmg",
                "--pattern", "SHA256SUMS", "--dir", temporary)
        checksum = verify_downloads(directory, version, assets)
        macos = inspect(directory / f"Luma-{version}-arm64.dmg", version)
        current = json.loads(command("gh", "api", api_path))
        _, current_assets = release_assets(current, tag)
        identity_fields = ["id", "name", "size", "state", "digest", "browser_download_url", "created_at", "updated_at"]
        def identities(items):
            return {name: {field: asset.get(field) for field in identity_fields} for name, asset in items.items()}
        if release.get("id") != current.get("id") or identities(assets) != identities(current_assets):
            raise ValueError("Published release/assets changed during verification; retry before updating the cask")
        cask = render_cask(version, checksum, macos)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Withhold the old/new cask replacement until every validation succeeds.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent, delete=False) as staged:
        staged.write(cask)
        staged_path = Path(staged.name)
    try:
        staged_path.chmod(0o644)
        os.replace(staged_path, output)
    finally:
        staged_path.unlink(missing_ok=True)
    return {"repository": REPOSITORY, "tag": tag, "asset": assets[f"Luma-{version}-arm64.dmg"]["browser_download_url"],
            "sha256": checksum, "architecture": "arm64", "minimumMacOS": "26.0", "bundleID": "app.luma.mac"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", type=Path, default=Path("Distribution/Homebrew/Casks/luma.rb"))
    args = parser.parse_args()
    try:
        result = prepare(args.tag, args.output)
        print(json.dumps(result, indent=2, sort_keys=True))
        print(f"Prepared {args.output}. Review the diff and Homebrew checks before committing it to the tap.")
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Cask preparation failed; existing cask left unchanged: {error}\n")


if __name__ == "__main__":
    main()
