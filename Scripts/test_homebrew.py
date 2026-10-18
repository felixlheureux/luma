import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from prepare_homebrew import BASE_URL, prepare, render_cask, validate_payload


class ReleaseFixture:
    def __init__(self):
        self.image = b"disposable image fixture"
        self.digest = hashlib.sha256(self.image).hexdigest()
        self.manifest = f"{self.digest}  Luma-0.2.0-arm64.dmg\n".encode()
        self.release = {"id": 1, "tag_name": "v0.2.0", "draft": False,
                        "published_at": "2026-10-17T23:08:46Z", "prerelease": True, "assets": []}
        for index, (name, data) in enumerate([("Luma-0.2.0-arm64.dmg", self.image), ("SHA256SUMS", self.manifest)]):
            self.release["assets"].append({"id": index + 10, "name": name, "size": len(data), "state": "uploaded",
                                            "browser_download_url": f"{BASE_URL}/v0.2.0/{name}",
                                            "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                                            "updated_at": "2026-10-17T23:08:46Z", "download_count": 1})
        self.calls = []
        self.after = None
        self.inspect_error = None

    def command(self, *args):
        self.calls.append(args)
        if args[1] == "api":
            result = copy.deepcopy(self.release)
            if self.after and sum(call[1] == "api" for call in self.calls) > 1:
                self.after(result)
            return json.dumps(result)
        directory = Path(args[-1])
        (directory / "Luma-0.2.0-arm64.dmg").write_bytes(self.image)
        (directory / "SHA256SUMS").write_bytes(self.manifest)
        return ""

    def inspect(self, image, version):
        if self.inspect_error:
            raise self.inspect_error
        assert image.read_bytes() == self.image and version == "0.2.0"
        return "tahoe"


class HomebrewPreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.output = Path(self.directory.name) / "Casks/luma.rb"
        self.output.parent.mkdir()
        self.output.write_text("original cask\n")

    def check_rejected(self, fixture):
        with self.assertRaises(ValueError):
            prepare("v0.2.0", self.output, fixture.inspect, fixture.command)
        self.assertEqual(self.output.read_text(), "original cask\n")
        self.assertEqual(sorted(p.name for p in self.output.parent.iterdir()), ["luma.rb"])

    def test_verified_prerelease_writes_reviewable_app_only_cask(self):
        fixture = ReleaseFixture()
        result = prepare("v0.2.0", self.output, fixture.inspect, fixture.command)
        text = self.output.read_text()
        self.assertIn('cask "luma" do', text)
        self.assertIn(f'sha256 "{fixture.digest}"', text)
        self.assertIn('uninstall quit: "app.luma.mac"', text)
        self.assertIn("depends_on arch: :arm64", text)
        self.assertIn("depends_on macos: :tahoe", text)
        for forbidden in ["zap ", "delete:", "trash:", "signal:", "system_command", "xattr", "no-quarantine", "preflight", "postflight"]:
            self.assertNotIn(forbidden, text)
        self.assertEqual(result["sha256"], fixture.digest)

    def test_missing_duplicate_and_unpublished_assets_leave_cask_unchanged(self):
        for mutation in [
            lambda r: r.update(draft=True), lambda r: r.update(published_at=None),
            lambda r: r.update(tag_name="v0.1.2"), lambda r: r["assets"].pop(),
            lambda r: r["assets"].append(copy.deepcopy(r["assets"][0])),
            lambda r: r["assets"][0].update(state="new"),
            lambda r: r["assets"][0].update(browser_download_url="https://example.com/app.dmg"),
            lambda r: r["assets"][0].update(size=0),
            lambda r: r["assets"][0].update(size=1_073_741_825),
        ]:
            with self.subTest(mutation=mutation):
                fixture = ReleaseFixture(); mutation(fixture.release); self.check_rejected(fixture)

    def test_corrupt_download_or_checksum_never_updates(self):
        for mutation in [
            lambda f: setattr(f, "image", b"changed"),
            lambda f: setattr(f, "manifest", b"changed"),
            lambda f: f.release["assets"][0].update(digest="sha256:" + "0" * 64),
        ]:
            fixture = ReleaseFixture(); mutation(fixture); self.check_rejected(fixture)
        for manifest in [b"not a checksum", b"0" * 64 + b"  Other.dmg\n", b"0" * 64 + b"  Luma-0.2.0-arm64.dmg\n"]:
            fixture = ReleaseFixture(); fixture.manifest = manifest
            fixture.release["assets"][1].update(size=len(manifest), digest="sha256:" + hashlib.sha256(manifest).hexdigest())
            self.check_rejected(fixture)

    def test_duplicate_manifest_or_payload_failure_leaves_old_cask(self):
        fixture = ReleaseFixture(); fixture.manifest *= 2
        fixture.release["assets"][1].update(size=len(fixture.manifest), digest=None)
        self.check_rejected(fixture)
        fixture = ReleaseFixture(); fixture.inspect_error = ValueError("wrong app identity or invalid signature")
        self.check_rejected(fixture)

    def test_asset_mutation_is_rejected_but_download_counters_can_change(self):
        fixture = ReleaseFixture()
        fixture.after = lambda r: r["assets"][0].update(updated_at="2026-10-18T00:00:00Z")
        self.check_rejected(fixture)
        fixture = ReleaseFixture()
        fixture.after = lambda r: r["assets"][0].update(download_count=2)
        prepare("v0.2.0", self.output, fixture.inspect, fixture.command)
        self.assertIn('cask "luma" do', self.output.read_text())

    def test_invalid_tags_cannot_reach_command_or_output(self):
        for tag in ["latest", "v0.2", "0.2.0", "v0.2.0-beta", "v00.2.0", "v$(touch injected)", "v0.2.0/../../"]:
            fixture = ReleaseFixture()
            with self.assertRaises(ValueError):
                prepare(tag, self.output, fixture.inspect, fixture.command)
            self.assertEqual(fixture.calls, [])
            self.assertEqual(self.output.read_text(), "original cask\n")
        with self.assertRaises(ValueError):
            render_cask('0.2.0"; system("bad")', "0" * 64, "tahoe")

    def test_metadata_architecture_and_both_deployment_targets_must_agree(self):
        info = {"CFBundleIdentifier": "app.luma.mac", "CFBundleShortVersionString": "0.2.0",
                "CFBundleExecutable": "Luma", "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0"}
        build = "platform MACOS\nminos 26.0\n"
        self.assertEqual(validate_payload(info, "arm64\n", build, "0.2.0"), "tahoe")
        for key, value in [("CFBundleIdentifier", "other.app"), ("CFBundleShortVersionString", "0.1.2"),
                           ("CFBundleExecutable", "../elsewhere"), ("LSMinimumSystemVersion", "26.1"),
                           ("LSMinimumSystemVersion", "27.0")]:
            bad = dict(info); bad[key] = value
            with self.assertRaises(ValueError): validate_payload(bad, "arm64", build, "0.2.0")
        for arch in ["x86_64", "arm64 x86_64", ""]:
            with self.assertRaises(ValueError): validate_payload(info, arch, build, "0.2.0")
        for bad in ["platform IOS\nminos 26.0\n", "platform MACOS\nminos 27.0\n", "", build + build]:
            with self.assertRaises(ValueError): validate_payload(info, "arm64", bad, "0.2.0")


if __name__ == "__main__":
    unittest.main()
