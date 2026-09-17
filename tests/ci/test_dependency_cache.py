import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dependency_cache', ROOT / 'scripts/ci/cache-macos-client.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class DependencyCacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'source'
        self.deps = Path(self.tmp.name) / 'deps'
        self.tools = {'arch': 'arm64', 'sdk': '27', 'compiler': 'fixture'}
        for name in (*cache.INPUTS, cache.PATCH):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')

    def key(self):
        return cache.fingerprint(self.root, self.deps, self.tools)

    def test_application_changes_reuse_dependencies(self):
        key = self.key()
        (self.root / 'VERSION').write_text('new version')
        (self.root / 'apps/client/app/example.cpp').write_text('new application')
        self.assertEqual(key, self.key())
        self.assertTrue(cache.key_valid(key))

    def test_every_required_input_invalidates_cache(self):
        key = self.key()
        for name in (*cache.INPUTS, cache.PATCH):
            path = self.root / name
            path.write_text('changed')
            self.assertNotEqual(key, self.key(), name)
            path.write_text('fixture')
        (self.root / cache.PATCH).with_name('another.patch').write_text('patch')
        self.assertNotEqual(key, self.key())

    def test_missing_patch_is_fatal(self):
        (self.root / cache.PATCH).unlink()
        with self.assertRaises(FileNotFoundError):
            self.key()

    def test_deployment_targets_never_share_dependencies(self):
        with patch.dict(cache.os.environ, {}, clear=True):
            default = self.key()
        with patch.dict(cache.os.environ, {'PLANK_MAC_CLIENT_MIN_MACOS': '27.0'}):
            self.assertEqual(default, self.key())
        with patch.dict(cache.os.environ, {'PLANK_MAC_CLIENT_MIN_MACOS': '15.0'}):
            self.assertNotEqual(default, self.key())
        with patch.dict(cache.os.environ, {'PLANK_MAC_CLIENT_MIN_MACOS': '14.0'}):
            with self.assertRaises(ValueError):
                self.key()

    def test_toolchain_and_paths_are_exact(self):
        key = self.key()
        for name in self.tools:
            changed = dict(self.tools, **{name: 'different'})
            self.assertNotEqual(key, cache.fingerprint(self.root, self.deps, changed))
        self.assertNotEqual(key, cache.fingerprint(self.root, self.deps / 'other', self.tools))

    def test_paths_exclude_application_and_credentials(self):
        self.assertEqual([str(p.relative_to(self.deps)) for p in cache.cache_paths(self.deps)], [
            'macos-client/install', 'macos-client/src', 'macos-client/downloads',
            'qt', 'macos-client/cache-receipt.json'])

    def test_receipt_rejects_mismatch_and_missing_state(self):
        key = self.key()
        receipt = cache.cache_paths(self.deps)[-1]
        receipt.parent.mkdir(parents=True)
        for data in ({'schema': 2, 'key': key}, {'schema': 1, 'key': key + 'bad'}):
            receipt.write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                cache.verify_receipt(self.deps, key)
        receipt.write_text(json.dumps({'schema': 1, 'key': key}))
        cache.verify_receipt(self.deps, key)
        self.assertFalse(cache.key_valid(key + 'bad'))
        receipt.unlink()
        with self.assertRaises(FileNotFoundError):
            cache.verify_receipt(self.deps, key)

    def test_prepared_patch_is_independently_verified(self):
        with self.assertRaises(ValueError):
            cache.check_prepared(self.root, self.deps)
        for name in ('macos-client/install/lib/libavcodec.dylib', 'qt/6.10.2/macos/bin/qmake'):
            path = self.deps / name
            path.parent.mkdir(parents=True)
            path.touch()
        with patch.object(cache.subprocess, 'run') as run:
            cache.check_prepared(self.root, self.deps)
            self.assertIn('--reverse', run.call_args.args[0])
            self.assertIn('--dry-run', run.call_args.args[0])
            self.assertTrue(run.call_args.kwargs['check'])

    def test_workflow_has_exact_restore_and_trusted_save(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertEqual(workflow.count('actions/cache/restore@caa296126883cff596d87d8935842f9db880ef25'), 4)
        self.assertEqual(workflow.count('actions/cache/save@caa296126883cff596d87d8935842f9db880ef25'), 4)
        self.assertNotIn('restore-keys:', workflow)
        self.assertEqual(workflow.count('test "$MATCHED_KEY" = "$CACHE_KEY"'), 4)
        unsigned = workflow.split('  macos-signed:')[0]
        for save in unsigned.split('- name: Save dependencies')[1:]:
            save = save.split('- name:')[0]
            self.assertIn("github.event_name != 'pull_request'", save)
            self.assertIn('!inputs.clean_bootstrap', save)
        signed = workflow.split('  macos-signed:')[1]
        self.assertLess(signed.index('Remove temporary signing material'), signed.index('Save dependencies'))


if __name__ == '__main__':
    unittest.main()
