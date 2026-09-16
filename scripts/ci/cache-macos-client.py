#!/usr/bin/env python3
"""Exact-input prepared-library cache. No app objects, accounts or signing state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess

INPUTS = (
    'scripts/ci/cache-macos-client.py',
    'scripts/ci/bootstrap.sh',
    'scripts/build/bootstrap-macos-client-deps.sh',
    'scripts/build/prepare-macos-sdl.sh',
    'scripts/build/build-paths.sh',
    'scripts/build/relocate-openssl-pc.py',
    'scripts/build/sanitize-ffmpeg-build-info.py',
)
PATCH = 'apps/client/app/deploy/linux/ffmpeg-patches/0001-hevc-enable-hwaccel-for-identity-gbr.patch'
SDL_PATCH = 'apps/client/app/deploy/macos/sdl-patches/0001-cocoa-opt-in-full-display-content-size.patch'
KEY_PREFIX = 'plank-macos-client-deps-v1-'


def fingerprint(root, dependency_root, toolchain):
    paths = set(INPUTS) | {PATCH, SDL_PATCH}
    paths.update(str(p.relative_to(root)) for p in (root / Path(PATCH).parent).glob('*.patch'))
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sorted(paths)}
    # Prepared .pc/CMake/dylib metadata has absolute build prefixes. Never reuse
    # it under a different path, SDK, compiler or OS image. App/version changes
    # deliberately do not invalidate these independent libraries.
    data = {'schema': 1, 'inputs': hashes, 'source_root': str(root),
            'dependency_root': str(dependency_root), 'toolchain': toolchain}
    return KEY_PREFIX + hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def cache_paths(deps):
    return [deps / 'macos-client/install', deps / 'macos-client/src',
            deps / 'macos-client/downloads', deps / 'qt',
            deps / 'macos-client/cache-receipt.json']


def key_valid(key):
    return re.fullmatch(re.escape(KEY_PREFIX) + '[0-9a-f]{64}', key) is not None


def verify_receipt(deps, key):
    if not key_valid(key):
        raise ValueError('Invalid dependency cache key')
    receipt = json.loads(cache_paths(deps)[-1].read_text())
    if receipt != {'schema': 1, 'key': key}:
        raise ValueError('Restored dependency cache does not match exact inputs')


def check_prepared(root, deps):
    for relative in ('macos-client/install/lib/libavcodec.dylib', 'qt/6.10.2/macos/bin/qmake'):
        if not (deps / relative).is_file():
            raise ValueError('Incomplete prepared dependency cache')
    subprocess.run(['bash', str(root / 'scripts/build/prepare-macos-sdl.sh'),
                    'verify', str(root), str(deps / 'macos-client')], check=True)
    # Check the required source patch independently of a cache-hit claim.
    with (root / PATCH).open('rb') as patch:
        subprocess.run(['patch', '--batch', '--reverse', '--dry-run', '-p1',
                        '-d', str(deps / 'macos-client/src/ffmpeg-9.0.1')], stdin=patch, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('prepare', 'verify', 'seal'))
    parser.add_argument('--key')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Cache is qualified only for the Apple Silicon Mac Client builder')
    root = Path(os.environ['PLANK_SOURCE_ROOT']).resolve()
    deps = Path(os.environ['PLANK_DEP_ROOT']).resolve()
    if args.operation == 'prepare':
        # Resolve patch bytes, not the whole Client commit: a UI-only commit
        # must not force FFmpeg/OpenSSL/SDL/Qt to be rebuilt.
        subprocess.run(['git', '-C', str(root), 'submodule', 'update', '--init', 'apps/client'], check=True)
        commands = (['sw_vers', '-productVersion'], ['sw_vers', '-buildVersion'],
                    ['xcodebuild', '-version'], ['xcrun', '--sdk', 'macosx', '--show-sdk-version'],
                    ['xcrun', '--sdk', 'macosx', '--show-sdk-build-version'],
                    ['xcrun', 'clang', '--version'], ['cmake', '--version'],
                    ['ninja', '--version'], ['python3', '--version'])
        toolchain = {'architecture': platform.machine(), 'runner_image': os.environ.get('ImageVersion', ''),
                     'tools': [subprocess.check_output(c, text=True).strip() for c in commands]}
        key = fingerprint(root, deps, toolchain)
        paths = '\n'.join(str(p) for p in cache_paths(deps))
        if any(c in str(root) + str(deps) for c in ('\n', '\r')):
            raise ValueError('Invalid builder path')
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'key={key}\npaths<<PLANK_CACHE_PATHS\n{paths}\nPLANK_CACHE_PATHS\n')
        print('macos_client_dependency_cache_key=' + key)
        return
    if not key_valid(args.key or ''):
        raise ValueError('Exact dependency key required')
    if args.operation == 'verify':
        verify_receipt(deps, args.key)
    check_prepared(root, deps)
    if args.operation == 'seal':
        cache_paths(deps)[-1].write_text(json.dumps({'schema': 1, 'key': args.key}, sort_keys=True) + '\n')
    print('macos_client_dependency_cache_' + args.operation + '=pass')


if __name__ == '__main__':
    main()
