import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('product_cache', ROOT / 'scripts/ci/cache-dependencies.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class ProductDependencyCacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'source'
        self.deps = Path(self.tmp.name) / 'deps'
        self.tools = {'architecture': 'fixture', 'sdk': 'fixture', 'packages': ['lib=1']}
        for name in (*cache.COMMON_INPUTS, cache.IDENTITY_PATCH,
                     'scripts/ci/install-linux-deps.sh', 'scripts/build/build-client-ffmpeg.sh',
                     'scripts/build/sanitize-ffmpeg-build-info.py',
                     'third_party/quinn-proto-0.11.17/Cargo.toml',
                     'third_party/quinn-proto-0.11.17/Cargo.lock',
                     'scripts/build/verify-host-dependency-patches.sh'):
            self.write(self.root / name, 'fixture')
        self.host_deps = self.root / cache.HOST_DEPS
        self.write(self.host_deps / 'CMakeLists.txt', 'fixture')
        subprocess.run(['git', 'init', '-q', str(self.host_deps)], check=True)
        subprocess.run(['git', '-C', str(self.host_deps), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.host_deps), '-c', 'user.name=CI fixture',
                        '-c', 'user.email=ci@example.org', 'commit', '-qm', 'Fixture'], check=True)

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def key(self, product):
        return cache.fingerprint(self.root, self.deps, product, self.tools)

    def test_application_changes_do_not_invalidate(self):
        for product in cache.PRODUCTS[:-1]:
            key = self.key(product)
            self.write(self.root / 'packaging/VERSION', 'new')
            self.write(self.root / 'apps/host/macos/example.m', 'new')
            self.write(self.root / 'apps/client/app/example.cpp', 'new')
            self.assertEqual(key, self.key(product))
            self.assertTrue(cache.key_valid(key, product))

    def test_shared_inputs_invalidate_all_new_caches(self):
        for product in cache.PRODUCTS[:-1]:
            key = self.key(product)
            for name in cache.COMMON_INPUTS:
                self.write(self.root / name, 'changed')
                self.assertNotEqual(key, self.key(product), name)
                self.write(self.root / name, 'fixture')

    def test_client_patch_and_build_flags_invalidate(self):
        key = self.key('linux-client')
        for name in (cache.IDENTITY_PATCH, 'scripts/build/build-client-ffmpeg.sh'):
            self.write(self.root / name, 'changed')
            self.assertNotEqual(key, self.key('linux-client'))
            self.write(self.root / name, 'fixture')
        self.write(self.root / cache.CLIENT_PATCHES / 'new.patch', 'patch')
        self.assertNotEqual(key, self.key('linux-client'))

    def test_host_dependency_source_and_pin_invalidate(self):
        key = self.key('linux-host')
        self.write(self.host_deps / 'CMakeLists.txt', 'changed')
        self.assertNotEqual(key, self.key('linux-host'))
        self.write(self.host_deps / 'CMakeLists.txt', 'fixture')
        with patch.object(cache, 'output', side_effect=lambda cmd: '0' * 40 if 'rev-parse' in cmd else '100644 ' + '1' * 40 + ' 0\tCMakeLists.txt'):
            self.assertNotEqual(key, self.key('linux-host'))

    def test_host_vendor_test_dependencies_invalidate(self):
        key = self.key('linux-host')
        for name in ('Cargo.toml', 'Cargo.lock'):
            path = self.root / 'third_party/quinn-proto-0.11.17' / name
            self.write(path, 'changed')
            self.assertNotEqual(key, self.key('linux-host'))
            self.write(path, 'fixture')

    def test_host_gitlinks_are_pins_not_regular_files(self):
        with patch.object(cache, 'output', side_effect=lambda cmd: '0' * 40 if 'rev-parse' in cmd else '160000 ' + '1' * 40 + ' 0\tFFmpeg/source'):
            key = self.key('linux-host')
        with patch.object(cache, 'output', side_effect=lambda cmd: '0' * 40 if 'rev-parse' in cmd else '160000 ' + '2' * 40 + ' 0\tFFmpeg/source'):
            self.assertNotEqual(key, self.key('linux-host'))

    def test_toolchain_paths_and_products_are_distinct(self):
        keys = []
        for product in cache.PRODUCTS[:-1]:
            key = self.key(product)
            keys.append(key)
            self.assertNotEqual(key, cache.fingerprint(self.root, self.deps / 'other', product, self.tools))
            self.assertNotEqual(key, cache.fingerprint(self.root, self.deps, product, dict(self.tools, sdk='changed')))
            self.assertNotEqual(key, cache.fingerprint(self.root, self.deps, product, dict(self.tools, packages=['lib=2'])))
        self.assertEqual(len(set(keys)), 3)

    def test_missing_inputs_fail_closed(self):
        (self.root / cache.IDENTITY_PATCH).unlink()
        with self.assertRaises(FileNotFoundError):
            self.key('linux-client')

    def test_cache_paths_are_dependency_only(self):
        common = ['rustup', 'cargo/bin', 'cargo/registry/cache', 'cargo/registry/index',
                  'cargo/registry/src', 'cargo/git/db', 'cargo/git/checkouts']
        for product in cache.PRODUCTS[:-1]:
            paths = cache.cache_paths(self.root, self.deps, product)
            expected = [self.deps / name for name in common]
            if product == 'linux-host':
                expected += [self.deps / 'host-ffmpeg', self.deps / 'boost-1.89.0', self.host_deps / 'build']
            elif product == 'linux-client':
                expected += [self.deps / 'client-ffmpeg/install', self.deps / 'client-ffmpeg/ffmpeg-9.0.1',
                             self.deps / 'client-ffmpeg/ffmpeg-9.0.1.tar.xz']
            expected.append(self.deps / (product + '-cache-receipt.json'))
            self.assertEqual(paths, expected)
            for path in paths:
                self.assertNotIn('credentials', str(path))
                self.assertNotIn('target', path.parts)

    def test_receipt_is_exact_and_product_specific(self):
        for product in cache.PRODUCTS[:-1]:
            key = self.key(product)
            receipt = cache.cache_paths(self.root, self.deps, product)[-1]
            self.write(receipt, json.dumps({'schema': 1, 'key': key}))
            cache.verify_receipt(self.root, self.deps, product, key)
            self.assertFalse(cache.key_valid(key, 'another-product'))
            self.write(receipt, json.dumps({'schema': 1, 'key': key + 'bad'}))
            with self.assertRaises(ValueError):
                cache.verify_receipt(self.root, self.deps, product, key)
            receipt.unlink()
            with self.assertRaises(FileNotFoundError):
                cache.verify_receipt(self.root, self.deps, product, key)

    def test_prepared_source_patch_checks_cannot_be_skipped(self):
        for product in cache.PRODUCTS[:-1]:
            with self.assertRaises(ValueError):
                cache.check_prepared(self.root, self.deps, product)
        for name in ('cargo/bin/rustup', 'rustup/settings.toml', 'host-ffmpeg/lib/libavcodec.a',
                     'host-ffmpeg/lib/libavutil.a', 'boost-1.89.0/CMakeLists.txt',
                     'client-ffmpeg/ffmpeg-9.0.1.tar.xz',
                     *(f'client-ffmpeg/install/lib/{name}.so' for name in
                       ('libavcodec', 'libavutil', 'libswscale', 'libswresample'))):
            self.write(self.deps / name, 'fixture')
        for product in ('linux-client', 'linux-host'):
            with patch.object(cache.subprocess, 'run') as run:
                cache.check_prepared(self.root, self.deps, product)
                self.assertTrue(run.call_args.kwargs['check'])
                if product == 'linux-client':
                    self.assertIn('--reverse', run.call_args.args[0])
                    self.assertIn('--dry-run', run.call_args.args[0])
                else:
                    self.assertIn('verify-host-dependency-patches.sh', run.call_args.args[0][1])
        cache.check_prepared(self.root, self.deps, 'macos-host')
        (self.deps / 'client-ffmpeg/ffmpeg-9.0.1.tar.xz').unlink()
        with self.assertRaises(ValueError):
            cache.check_prepared(self.root, self.deps, 'linux-client')

    def test_all_products_wired_before_bootstrap_after_build(self):
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        for job in ('linux-host', 'linux-client', 'macos', 'macos-signed'):
            block = workflow.split(f'  {job}:\n')[1]
            # Cut only at the next job header, not a nested YAML field.
            block = re.split(r'\n  [a-z][a-z-]+:\n', block)[0]
            self.assertIn('!inputs.clean_bootstrap', block)
            self.assertLess(block.index('Select exact dependency inputs'), block.index('Restore dependencies'))
            self.assertLess(block.index('Restore dependencies'), block.index('Verify exact restored dependencies'))
            self.assertLess(block.index('Verify exact restored dependencies'), block.index('Seal successful dependencies'))
            self.assertNotIn('restore-keys:', block)
            if job == 'macos-signed':
                self.assertIn("inputs.product != 'macos-fullscreen-probe'", block)
                self.assertLess(block.index('Remove temporary signing material'), block.index('Seal successful dependencies'))
            else:
                self.assertIn("github.event_name != 'pull_request'", block)


if __name__ == '__main__':
    unittest.main()
