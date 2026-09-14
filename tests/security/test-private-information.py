#!/usr/bin/env python3
"""Privacy checks use synthetic data in isolated temporary repositories."""
import base64
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'scripts/maintenance/check-private-information.py'
spec = importlib.util.spec_from_file_location('privacy_check', CHECK)
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PolicyTests(unittest.TestCase):
    def test_reserved_examples_and_network_definitions(self):
        data = b'192.0.2.10 198.51.100.20 203.0.113.30 127.0.0.1 0.0.0.0 10.0.0.0/8'
        self.assertEqual([], privacy.content_findings(data, True, []))

    def test_private_documentation_is_flagged_without_values(self):
        data = b'198.18.' + b'77.55 /home/' + b'person/project machine.' + b'internal'
        self.assertEqual({'non-example-ipv4', 'personal-home-path', 'internal-domain'},
                         set(privacy.content_findings(data, True, [])))

    def test_network_code_is_not_mistaken_for_deployment_notes(self):
        data = b'198.18.' + b'77.55'
        self.assertEqual([], privacy.content_findings(data, False, []))

    def test_force_adding_private_files_is_blocked(self):
        for path in ('passwords_audit.txt', 'private-notes/machines.md',
                     '.env', '.env.production', 'keys/signing.p12', 'tls/host.key'):
            self.assertEqual(['private-file-name'], privacy.path_findings(path))
        for path in ('.env.example', 'docs/security/private-information.md', 'packaging/config/host.conf'):
            self.assertEqual([], privacy.path_findings(path))


@unittest.skipUnless(shutil.which('gitleaks'), 'Gitleaks required for end-to-end guard tests')
class GitIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='plank-privacy-test-')
        self.base = Path(self.temporary.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
        for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR'):
            self.env.pop(key, None)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Privacy Test')
        self.git('config', 'user.email', 'test@example.org')
        self.git('commit', '--allow-empty', '-qm', 'Initial test state')
        self.initial = self.git('rev-parse', 'HEAD').stdout.strip()
        # This is fabricated test data, not a credential or deployment identifier.
        self.value = 'synthetic-' + self.base.name + '-fixture'
        self.denylist = self.base / 'denylist.txt'
        self.denylist.write_text(self.value + '\n')
        self.denylist.chmod(0o600)
        self.git('config', 'plank.privateDenylist', str(self.denylist))

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args):
        return subprocess.run(['git', *args], cwd=self.repo, env=self.env,
                              capture_output=True, text=True, check=True)

    def check(self, *args):
        result = subprocess.run([sys.executable, str(CHECK), *args], cwd=self.repo, env=self.env,
                                capture_output=True, text=True)
        self.assertNotIn(self.value, result.stdout + result.stderr)
        return result

    def stage(self, name, value):
        (self.repo / name).write_text(value)
        self.git('add', '--', name)

    def test_staged_secret_is_not_hidden_by_clean_worktree(self):
        self.stage('example.md', self.value)
        (self.repo / 'example.md').write_text('safe replacement not staged')
        self.assertEqual(1, self.check('--staged').returncode)

    def test_unstaged_content_does_not_contaminate_staged_check(self):
        self.stage('example.md', 'Public example: 192.0.2.10')
        (self.repo / 'example.md').write_text(self.value)
        self.assertEqual(0, self.check('--staged').returncode)

    def test_encoded_known_value_is_blocked(self):
        self.stage('example.md', base64.b64encode(self.value.encode()).decode())
        self.assertEqual(1, self.check('--staged').returncode)

    def test_binary_blob_and_filename_are_checked_without_exposure(self):
        name = self.value + '.bin'
        (self.repo / name).write_bytes(b'\0' + self.value.encode())
        self.git('add', '--', name)
        result = self.check('--staged')
        self.assertEqual(1, result.returncode)
        self.assertIn('[private filename]', result.stderr)

    def test_current_blob_denylist_covers_unchanged_lines(self):
        self.stage('example.md', self.value + '\nInitial prose.\n')
        self.git('commit', '-qm', 'Synthetic old content')
        self.stage('example.md', self.value + '\nEdited prose.\n')
        self.assertEqual(1, self.check('--staged').returncode)

    def test_commit_message_is_checked_and_redacted(self):
        message = self.base / 'message'
        message.write_text(self.value)
        self.assertEqual(1, self.check('--commit-msg', str(message)).returncode)

    def test_ci_sees_secret_introduced_then_removed(self):
        self.stage('example.md', self.value)
        self.git('commit', '-qm', 'Add synthetic test content')
        self.stage('example.md', 'Clean end state')
        self.git('commit', '-qm', 'Remove synthetic test content')
        self.assertEqual(1, self.check('--range', self.initial, 'HEAD').returncode)

    def test_clean_range_passes(self):
        self.stage('example.md', 'Use host.example.org or 192.0.2.10.')
        self.git('commit', '-qm', 'Document a reserved example')
        self.assertEqual(0, self.check('--range', self.initial, 'HEAD').returncode)

    def test_private_denylist_cannot_be_inside_checkout(self):
        copied = self.repo / 'list.txt'
        copied.write_text(self.value)
        copied.chmod(0o600)
        self.git('config', 'plank.privateDenylist', str(copied))
        self.assertEqual(2, self.check('--staged').returncode)

    def test_insecure_or_missing_configured_denylist_fails_closed(self):
        self.denylist.chmod(0o644)
        self.assertEqual(2, self.check('--staged').returncode)
        self.denylist.unlink()
        self.assertEqual(2, self.check('--staged').returncode)

    def test_private_denylist_cannot_be_inside_another_checkout(self):
        other = self.base / 'another-repo'
        other.mkdir()
        subprocess.run(['git', 'init', '-q', str(other)], env=self.env, check=True)
        copied = other / 'list.txt'
        copied.write_text(self.value)
        copied.chmod(0o600)
        self.git('config', 'plank.privateDenylist', str(copied))
        self.assertEqual(2, self.check('--staged').returncode)

    def test_literal_shell_password_is_blocked_without_denylist(self):
        self.git('config', '--unset', 'plank.privateDenylist')
        self.stage('example.sh', 'SSH' + 'PASS="synthetic-fixture-value"\n')
        self.assertEqual(1, self.check('--staged').returncode)

    def test_missing_scanner_blocks_commit(self):
        tools = self.base / 'tools'
        tools.mkdir()
        (tools / 'git').symlink_to(shutil.which('git'))
        self.env['PATH'] = str(tools)
        self.assertEqual(2, self.check('--staged').returncode)


if __name__ == '__main__':
    unittest.main()
