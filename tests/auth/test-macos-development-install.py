#!/usr/bin/env python3
"""Non-installing checks of development role identities; no services or OS input."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install-macos-host-development.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)
PUBLIC = {"Address": "0.0.0.0", "Port": 28989, "Name": "PLANK test",
          "UUID": "10d580de-73fa-4139-95ec-891804686ee2"}


class RoleIdentityTests(unittest.TestCase):
    def test_preserves_private_identity_and_does_not_share_keys(self):
        with tempfile.TemporaryDirectory(prefix="plank-role-identity-") as temporary:
            first, second = Path(temporary) / "first", Path(temporary) / "second"
            INSTALLER.prepare_sign_in_identity(first, PUBLIC)
            before = {p.name: p.read_bytes() for p in first.iterdir()}
            INSTALLER.prepare_sign_in_identity(first, PUBLIC)
            self.assertEqual(before, {p.name: p.read_bytes() for p in first.iterdir()})
            INSTALLER.prepare_sign_in_identity(second, PUBLIC)
            self.assertNotEqual((first / "key.der").read_bytes(), (second / "key.der").read_bytes())
            self.assertEqual((first / "host.plist").read_bytes(), (second / "host.plist").read_bytes())
            self.assertEqual(first.stat().st_mode & 0o777, 0o700)
            for path in first.iterdir():
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(AssertionError):
                INSTALLER.prepare_sign_in_identity(first, dict(PUBLIC, Port=12345))
            self.assertEqual(before, {p.name: p.read_bytes() for p in first.iterdir()})

    def test_rejects_partial_identity_without_overwriting_it(self):
        with tempfile.TemporaryDirectory(prefix="plank-role-identity-") as temporary:
            private = Path(temporary) / "partial"
            private.mkdir(mode=0o700)
            (private / "key.pem").write_text("preserve")
            with self.assertRaises(AssertionError):
                INSTALLER.prepare_sign_in_identity(private, PUBLIC)
            self.assertEqual((private / "key.pem").read_text(), "preserve")

    def test_rejects_symlink_and_public_directory(self):
        with tempfile.TemporaryDirectory(prefix="plank-role-identity-") as temporary:
            private, link = Path(temporary) / "private", Path(temporary) / "link"
            private.mkdir(mode=0o700)
            link.symlink_to(private, target_is_directory=True)
            with self.assertRaises(AssertionError):
                INSTALLER.prepare_sign_in_identity(link, PUBLIC)
            os.chmod(private, 0o755)
            with self.assertRaises(AssertionError):
                INSTALLER.prepare_sign_in_identity(private, PUBLIC)
            self.assertFalse(any(private.iterdir()))


if __name__ == "__main__":
    unittest.main()
