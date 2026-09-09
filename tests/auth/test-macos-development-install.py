#!/usr/bin/env python3
"""Non-installing checks of development role identities; no services or OS input."""
import importlib.util
import os
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("installer", ROOT / "scripts/install-macos-host-development.py")
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)
PUBLIC = {"Address": "0.0.0.0", "Port": 28989, "Name": "PLANK test",
          "UUID": "10d580de-73fa-4139-95ec-891804686ee2"}


class RoleIdentityTests(unittest.TestCase):
    def test_upgrade_keeps_requirement_and_team_before_any_mutation(self):
        with tempfile.TemporaryDirectory(prefix="plank-signature-") as temporary:
            source, installed = Path(temporary) / "source", Path(temporary) / "installed"
            source.mkdir()
            installed.mkdir()
            identity = ("ABCDEFGHIJ", 'identifier "la.instinctual.PLANK.Host" and anchor apple generic')
            with patch.object(INSTALLER, "signing_identity", return_value=identity) as check:
                INSTALLER.verify_upgrade_identity(source, installed)
                self.assertEqual([call.args[0] for call in check.call_args_list], [source, installed])
            for changed in (("KLMNOPQRST", identity[1]), (identity[0], "different requirement")):
                with patch.object(INSTALLER, "signing_identity", side_effect=[changed, identity]):
                    with self.assertRaisesRegex(ValueError, "preserving installed app"):
                        INSTALLER.verify_upgrade_identity(source, installed)
            script = (ROOT / "scripts/install-macos-host-development.py").read_text()
            self.assertLess(script.index("verify_upgrade_identity(source, installed)", script.index("def main")),
                            script.index("os.setegid(account.pw_gid)"))

    def test_first_install_still_checks_candidate(self):
        with tempfile.TemporaryDirectory(prefix="plank-signature-") as temporary:
            source, absent = Path(temporary) / "source", Path(temporary) / "absent"
            source.mkdir()
            with patch.object(INSTALLER, "signing_identity", return_value=("ABCDEFGHIJ", "requirement")) as check:
                INSTALLER.verify_upgrade_identity(source, absent)
                check.assert_called_once_with(source)

    def test_signature_rejects_symlinks_adhoc_and_missing_requirement(self):
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory(prefix="plank-signature-") as temporary:
            app, link = Path(temporary) / "app", Path(temporary) / "link"
            app.mkdir()
            link.symlink_to(app, target_is_directory=True)
            with self.assertRaises(ValueError):
                INSTALLER.signing_identity(link)
            with patch.object(INSTALLER, "run", return_value=SimpleNamespace(stderr="Signature=adhoc")):
                with self.assertRaises(ValueError):
                    INSTALLER.signing_identity(app)
            signature = "Authority=Apple Development: Test\nTeamIdentifier=ABCDEFGHIJ\n"
            with patch.object(INSTALLER, "run", side_effect=[SimpleNamespace(stderr=""),
                              SimpleNamespace(stderr=signature), SimpleNamespace(stdout="", stderr="")]):
                with self.assertRaisesRegex(ValueError, "designated"):
                    INSTALLER.signing_identity(app)

    def test_requirement_output_streams(self):
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory(prefix="plank-signature-") as temporary:
            app = Path(temporary)
            signature = "Authority=Apple Development: Test\nTeamIdentifier=ABCDEFGHIJ\n"
            requirement = 'identifier "la.instinctual.PLANK.Host" and anchor apple generic'
            line = "designated => " + requirement + "\n"
            for stdout, stderr in ((line, "Executable=/test\n"), ("", line)):
                with patch.object(INSTALLER, "run", side_effect=[SimpleNamespace(stderr=""),
                                  SimpleNamespace(stderr=signature), SimpleNamespace(stdout=stdout, stderr=stderr)]):
                    self.assertEqual(INSTALLER.signing_identity(app), ("ABCDEFGHIJ", requirement))
            with patch.object(INSTALLER, "run", side_effect=[SimpleNamespace(stderr=""),
                              SimpleNamespace(stderr=signature), SimpleNamespace(stdout=line, stderr=line)]):
                with self.assertRaisesRegex(ValueError, "unambiguous"):
                    INSTALLER.signing_identity(app)

    def test_host_icon_is_generated_from_shared_client_artwork(self):
        info = plistlib.loads((ROOT / "packaging/macos/host-info.plist").read_bytes())
        self.assertEqual(info["CFBundleIconFile"], "plank.icns")
        build = (ROOT / "scripts/build-macos-host.sh").read_text()
        self.assertIn('branding/assets/plank-logo.png', build)
        self.assertIn('Contents/Resources/plank.icns', build)
        self.assertLess(build.index('iconutil -c icns'), build.index('codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY"'))

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
