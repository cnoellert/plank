import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_context', ROOT / 'scripts/ci/context.py')
context = importlib.util.module_from_spec(spec)
spec.loader.exec_module(context)


class ContextTests(unittest.TestCase):
    def test_main_stays_unqualified(self):
        self.assertEqual(context.branch_name('main'), 'main')

    def test_normal_branch_is_preserved(self):
        self.assertEqual(context.branch_name('github-builds'), 'github-builds')

    def test_normalization_cannot_impersonate_main(self):
        self.assertNotEqual(context.branch_name('MAIN'), 'main')
        self.assertNotEqual(context.branch_name('main/'), 'main')

    def test_normalization_keeps_distinct_refs_distinct(self):
        self.assertNotEqual(context.branch_name('fix/a'), context.branch_name('fix-a'))
        self.assertRegex(context.branch_name('fix/a'), r'^fix-a-[0-9a-f]{8}$')

    def test_empty_names_rejected(self):
        for name in ['', '/', '___']:
            with self.assertRaises(ValueError):
                context.branch_name(name)

    def test_worktree_and_explicit_path_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / 'checkout'
            source.mkdir()
            subprocess.run(['git', 'init', '-q', str(source)], check=True)
            subprocess.run(['git', '-C', str(source), '-c', 'user.name=CI fixture',
                            '-c', 'user.email=ci@example.org', 'commit', '-q',
                            '--allow-empty', '-m', 'Fixture'], check=True)
            sha = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
            env_file = base / 'github-env'
            env = dict(os.environ, GITHUB_WORKSPACE=str(source), RUNNER_TEMP=str(base),
                       GITHUB_SHA=sha, EXPECTED_SOURCE_SHA=sha,
                       BUILD_REF='feature/check', GITHUB_ENV=str(env_file))
            subprocess.run(['python3', str(ROOT / 'scripts/ci/context.py')], env=env, check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            values = dict(line.split('=', 1) for line in env_file.read_text().splitlines())
            worktree = base / 'plank-ci/source'
            self.assertEqual(values['PLANK_SOURCE_ROOT'], str(worktree))
            self.assertEqual(values['PLANK_BUILD_BRANCH'], context.branch_name('feature/check'))
            self.assertEqual(subprocess.check_output(['git', '-C', str(worktree), 'rev-parse', 'HEAD'], text=True).strip(), sha)
            # Reusing a scratch root must fail instead of trusting stale outputs.
            self.assertNotEqual(subprocess.run(['python3', str(ROOT / 'scripts/ci/context.py')], env=env,
                                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode, 0)

    def test_untrusted_workflow_has_no_signing_or_write_authority(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        for forbidden in ['pull_request_target', 'secrets.', 'contents: write', 'self-hosted']:
            self.assertNotIn(forbidden, workflow)
        self.assertIn('contents: read', workflow)
        actions = re.findall(r'uses: ([^\s]+)', workflow)
        self.assertTrue(actions)
        for action in actions:
            self.assertRegex(action, r'@([0-9a-f]{40})$')
        self.assertEqual(workflow.count('actions/checkout@'), workflow.count('persist-credentials: false'))

    def test_all_root_workflows_use_current_node_actions(self):
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            workflow = path.read_text()
            for action in re.findall(r'uses: (actions/checkout@[^\s]+)', workflow):
                self.assertEqual(action, 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803')


if __name__ == '__main__':
    unittest.main()
