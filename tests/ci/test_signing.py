import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('signing', ROOT / 'scripts/ci/sign-macos.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def test_identity_is_exact_type_and_team(self):
        digest = 'A' * 40
        value = f'1) {digest} "Developer ID Application: Example (ABCDEFGHIJ)"'
        self.assertEqual(signing.signing_identity(value, 'Developer ID Application', 'ABCDEFGHIJ'), digest)
        for kind, team, output in (
                ('Developer ID Installer', 'ABCDEFGHIJ', value),
                ('Developer ID Application', 'KLMNOPQRST', value),
                ('Developer ID Application', 'ABCDEFGHIJ', value + '\n' + value)):
            with self.assertRaises(signing.SigningError):
                signing.signing_identity(output, kind, team)

    def test_rejects_local_and_untrusted_execution(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(signing.SigningError):
                signing.runner_directory()

    def test_tool_failure_cannot_echo_credentials(self):
        result = subprocess.CompletedProcess(['fixture'], 1, 'sensitive output', 'sensitive error')
        with patch.object(signing.subprocess, 'run', return_value=result):
            with self.assertRaises(signing.SigningError) as failure:
                signing.command('import fixture', ['fixture', 'sensitive argument'])
        self.assertNotIn('sensitive', str(failure.exception))

    def test_cleanup_restores_search_list_and_removes_material(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'plank-macos-signing'
            directory.mkdir(mode=0o700)
            (directory / 'search-list.json').write_text('["/example/login.keychain-db"]')
            (directory / 'signing.keychain-db').touch()
            (directory / 'application.p12').touch()
            with patch.object(signing, 'command') as command:
                signing.cleanup(directory)
            self.assertEqual(command.call_count, 2)
            self.assertIn('/example/login.keychain-db', command.call_args_list[0].args[1])
            self.assertFalse(directory.exists())

    def test_missing_secret_prevents_keychain_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'plank-macos-signing'
            with patch.dict(os.environ, {'PLANK_CI_PRODUCT': 'macos-host', 'PLANK_MACOS_TEAM_ID': 'ABCDEFGHIJ'}, clear=True), \
                    patch.object(signing, 'runner_directory', return_value=directory), \
                    patch.object(signing.sys, 'argv', ['sign-macos.py']), \
                    patch.object(signing, 'command') as command:
                with self.assertRaises(signing.SigningError):
                    signing.main()
                command.assert_not_called()
            self.assertFalse(directory.exists())


if __name__ == '__main__':
    unittest.main()
