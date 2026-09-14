#!/usr/bin/env python3
"""Repository-only artifact tests; dummy payloads never claim package validation."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('collector', ROOT / 'scripts/package/collect-package.py')
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'packaging').mkdir()
        (self.root / 'packaging/VERSION').write_text('1.2.3\n')
        def git(*args):
            return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.DEVNULL)
        git('init', '-b', 'main')
        git('add', 'packaging/VERSION')
        git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture')

    def arguments(self, branch='main', content=b'fixture'):
        suffix = '' if branch == 'main' else '-' + branch
        package = self.root / ('plank-client_1.2.3' + suffix + '_arm64.dmg')
        package.write_bytes(content)
        return SimpleNamespace(source_root=self.root, source_commit='HEAD', package=package,
            product='client', platform='macos', architecture='arm64', target_os='macos-27',
            branch=branch, validation='not-recorded', expected_sha256=None, output_root=None, move=False)

    def test_release_and_manifest(self):
        args = self.arguments()
        MODULE.collect(args)
        directory = self.root / 'artifacts/packages/releases/1.2.3'
        record = json.loads((directory / 'manifest.json').read_text())['packages'][0]
        self.assertEqual(record['validation']['functional'], 'not-recorded')
        self.assertEqual(record['sha256'], MODULE.digest(args.package))
        self.assertIn('macos/' + args.package.name, (directory / 'SHA256SUMS').read_text())
        MODULE.collect(args)  # Identical re-collection is safe.

    def test_candidate_and_move(self):
        args = self.arguments('feature-one')
        args.move = True
        MODULE.collect(args)
        self.assertFalse(args.package.exists())
        self.assertTrue((self.root / 'artifacts/packages/candidates/1.2.3-feature-one/macos' / args.package.name).is_file())

    def test_conflicting_package(self):
        args = self.arguments()
        MODULE.collect(args)
        args.package.write_bytes(b'different')
        with self.assertRaises(ValueError):
            MODULE.collect(args)

    def test_wrong_checksum(self):
        args = self.arguments()
        args.expected_sha256 = '0' * 64
        with self.assertRaises(ValueError):
            MODULE.collect(args)

    def test_wrong_branch_filename(self):
        args = self.arguments()
        args.branch = 'other'
        with self.assertRaises(ValueError):
            MODULE.collect(args)

    def test_provenance_conflict(self):
        args = self.arguments()
        MODULE.collect(args)
        args.target_os = 'another-os'
        with self.assertRaises(ValueError):
            MODULE.collect(args)


if __name__ == '__main__':
    unittest.main()
