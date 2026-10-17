import plistlib
from pathlib import Path
import tempfile
import unittest

from release_version import validate_version


class ReleaseVersionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "Resources").mkdir()
        self.write_version("0.1.3")

    def write_version(self, version):
        with (self.root / "Resources/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleShortVersionString": version}, output)
        (self.root / "Resources/Installer-ReadMe.txt").write_text(f"Luma {version} — Development Build\n")

    def test_matching_tag_and_manual_build(self):
        self.assertEqual(validate_version(self.root, "v0.1.3"), "0.1.3")
        self.assertEqual(validate_version(self.root), "0.1.3")

    def test_mismatched_and_malformed_tags_rejected(self):
        for tag in ["v0.1.2", "0.1.3", "v0.1.3-extra", "v$(touch unwanted)"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate_version(self.root, tag)

    def test_installer_version_drift_rejected(self):
        (self.root / "Resources/Installer-ReadMe.txt").write_text("Luma 0.1.2 — Development Build\n")
        with self.assertRaises(ValueError):
            validate_version(self.root, "v0.1.3")

    def test_invalid_bundle_versions_rejected(self):
        for version in ["", "0.1", "0.1.3-beta", 123]:
            with self.subTest(version=version):
                self.write_version(version)
                with self.assertRaises(ValueError):
                    validate_version(self.root)


if __name__ == "__main__":
    unittest.main()
