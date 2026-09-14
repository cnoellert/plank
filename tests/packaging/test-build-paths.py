#!/usr/bin/env python3
"""Build-privacy regression tests; use synthetic paths and non-product binaries."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


sanitize = module('sanitize', 'scripts/build/sanitize-ffmpeg-build-info.py').sanitize
check = module('check', 'scripts/test/check-package-build-paths.py').check


class BuildPaths(unittest.TestCase):
    def test_generated_configuration_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'config.h'
            other = '#define OTHER "/Users/build-operator/private/data"\n'
            path.write_text(other + '#define FFMPEG_CONFIGURATION "--prefix=/Users/build-operator/private/install --enable-vaapi"\n')
            sanitize(path, ['/Users/build-operator/private'])
            self.assertEqual(path.read_text(), other + '#define FFMPEG_CONFIGURATION "--prefix=/build/dependencies/install --enable-vaapi"\n')
            sanitize(path, ['/Users/build-operator/private'])  # Idempotent.

    def test_config_shape_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'config.h'
            for text in ('', '#define FFMPEG_CONFIGURATION "x"\n' * 2):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    sanitize(path, ['/private/build'])

    def test_payload_paths_and_symlink(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'binary'
            for value in (b'\0/home/build-operator/source\0', b'\0/Users/build-operator/source\0'):
                path.write_bytes(value)
                self.assertEqual(check(Path(tmp)), 1)
            path.write_bytes(b'\0/build/plank/source\0/usr/lib/libc.so\0')
            (Path(tmp) / 'Applications').symlink_to('/Applications')
            self.assertEqual(check(Path(tmp)), 0)

    def test_c_file_mapping(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source.c'
            source.write_text('#include <stdio.h>\nint main(void) { puts(__FILE__); }\n')
            script = '''set -eu
source "$1/scripts/build/build-paths.sh"
plank_build_path_flags "$2" "$2/output"
cc "${PLANK_FILE_FLAGS[@]}" "$2/source.c" -o "$2/test"
"$2/test"
'''
            result = subprocess.run(['bash', '-c', script, 'test', str(ROOT), tmp],
                                    text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout.strip(), '/build/plank/source/source.c')

    def test_rust_flags_preserved(self):
        script = '''set -eu
source "$1/scripts/build/build-paths.sh"
RUSTFLAGS='-C strip=none'
plank_build_path_flags /source /output
[[ $RUSTFLAGS == '-C strip=none '* ]]
[[ $RUSTFLAGS == *'--remap-path-prefix=/source=/build/plank/source'* ]]
'''
        subprocess.run(['bash', '-c', script, 'test', str(ROOT)], check=True)

    def test_encoded_flags_rejected(self):
        script = '''source "$1/scripts/build/build-paths.sh"
CARGO_ENCODED_RUSTFLAGS=override
plank_build_path_flags /source /output
'''
        result = subprocess.run(['bash', '-c', script, 'test', str(ROOT)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_all_package_entrypoints_enforce_gate(self):
        for name in ('host-rpm', 'client-deb', 'macos-host-pkg', 'macos-client-dmg'):
            self.assertIn('check-package-build-paths.py',
                          (ROOT / 'scripts/package' / ('build-' + name + '.sh')).read_text())


if __name__ == '__main__':
    unittest.main()
