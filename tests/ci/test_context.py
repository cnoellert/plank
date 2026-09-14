import importlib.util
from pathlib import Path
import re
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


if __name__ == '__main__':
    unittest.main()
