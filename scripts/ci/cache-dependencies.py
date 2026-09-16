#!/usr/bin/env python3
"""Exact-input hosted dependency caches; never application or signing state."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

PRODUCTS = ('linux-host', 'linux-client', 'macos-host', 'macos-client')
COMMON_INPUTS = (
    'scripts/ci/cache-dependencies.py', 'scripts/ci/bootstrap.sh',
    'scripts/build/build-paths.sh', 'rust-toolchain.toml',
    'protocol/plank-transport/Cargo.lock',
    'protocol/plank-transport/Cargo.toml',
)
HOST_DEPS = 'apps/host/linux/third-party/build-deps'
CLIENT_PATCHES = 'apps/client/app/deploy/linux/ffmpeg-patches'
IDENTITY_PATCH = CLIENT_PATCHES + '/0001-hevc-enable-hwaccel-for-identity-gbr.patch'


def output(command):
    return subprocess.check_output(command, text=True).strip()


def fingerprint(root, deps, product, toolchain):
    paths = set(COMMON_INPUTS)
    pins = {}
    if product.startswith('linux-'):
        paths.add('scripts/ci/install-linux-deps.sh')
    if product == 'linux-client':
        paths.update(('scripts/build/build-client-ffmpeg.sh',
                      'scripts/build/sanitize-ffmpeg-build-info.py', IDENTITY_PATCH))
        paths.update(str(p.relative_to(root)) for p in (root / CLIENT_PATCHES).glob('*.patch'))
    elif product == 'linux-host':
        paths.add('scripts/build/verify-host-dependency-patches.sh')
        # This dedicated submodule pins FFmpeg/x264/x265 sources, configuration,
        # patches and build commands independently of Host application changes.
        pins['host-build-deps'] = output(['git', '-C', str(root / HOST_DEPS), 'rev-parse', 'HEAD'])
        for entry in output(['git', '-C', str(root / HOST_DEPS), 'ls-files', '--stage']).splitlines():
            metadata, name = entry.split('\t', 1)
            mode, revision, stage = metadata.split()
            if stage != '0':
                raise ValueError('Unmerged dependency input')
            if mode == '160000':
                pins[name] = revision
            else:
                paths.add(HOST_DEPS + '/' + name)
    hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sorted(paths)}
    data = {'schema': 1, 'product': product, 'inputs': hashes, 'pins': pins,
            'source_root': str(root), 'dependency_root': str(deps), 'toolchain': toolchain}
    return f'plank-{product}-deps-v1-' + hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()


def cache_paths(root, deps, product):
    # Narrow Cargo allowlist: no credentials.toml, config, targets, or app
    # sources. Rust and downloaded crates are public, pinned bootstrap inputs.
    paths = [deps / name for name in (
        'rustup', 'cargo/bin', 'cargo/registry/cache', 'cargo/registry/index',
        'cargo/registry/src', 'cargo/git/db', 'cargo/git/checkouts')]
    if product == 'linux-host':
        paths += [deps / 'host-ffmpeg', deps / 'boost-1.89.0', root / HOST_DEPS / 'build']
    elif product == 'linux-client':
        paths += [deps / 'client-ffmpeg/install', deps / 'client-ffmpeg/ffmpeg-9.0.1']
    paths.append(deps / (product + '-cache-receipt.json'))
    return paths


def key_valid(key, product):
    return re.fullmatch(f'plank-{re.escape(product)}-deps-v1-[0-9a-f]{{64}}', key or '') is not None


def verify_receipt(root, deps, product, key):
    if not key_valid(key, product):
        raise ValueError('Invalid dependency cache key')
    receipt = json.loads(cache_paths(root, deps, product)[-1].read_text())
    if receipt != {'schema': 1, 'key': key}:
        raise ValueError('Restored dependency cache does not match exact inputs')


def check_prepared(root, deps, product):
    required = ['cargo/bin/rustup', 'rustup/settings.toml']
    if product == 'linux-host':
        required += ['host-ffmpeg/lib/libavcodec.a', 'host-ffmpeg/lib/libavutil.a',
                     'boost-1.89.0/CMakeLists.txt']
    elif product == 'linux-client':
        required += ['client-ffmpeg/install/lib/' + name + '.so'
                     for name in ('libavcodec', 'libavutil', 'libswscale', 'libswresample')]
    if any(not (deps / name).is_file() for name in required):
        raise ValueError('Incomplete prepared dependency cache')
    if product == 'linux-host':
        subprocess.run(['bash', str(root / 'scripts/build/verify-host-dependency-patches.sh'),
                        str(root / HOST_DEPS / 'build')], check=True)
    elif product == 'linux-client':
        with (root / IDENTITY_PATCH).open('rb') as patch:
            subprocess.run(['patch', '--batch', '--reverse', '--dry-run', '-p1', '-d',
                            str(deps / 'client-ffmpeg/ffmpeg-9.0.1')], stdin=patch, check=True)


def toolchain_inputs(product):
    commands = [['cmake', '--version'], ['ninja', '--version'], ['python3', '--version']]
    if product == 'macos-host':
        if platform.system() != 'Darwin' or platform.machine() != 'arm64':
            raise ValueError('Mac cache requires Apple Silicon')
        commands += [['sw_vers', '-productVersion'], ['sw_vers', '-buildVersion'],
                     ['xcodebuild', '-version'], ['xcrun', '--sdk', 'macosx', '--show-sdk-version'],
                     ['xcrun', '--sdk', 'macosx', '--show-sdk-build-version'], ['xcrun', 'clang', '--version']]
    else:
        if platform.system() != 'Linux' or platform.machine() != 'x86_64':
            raise ValueError('Linux cache requires the qualified x86_64 builder')
        commands += [['nasm', '-v'], ['make', '--version']]
        # Include exact installed versions, not a moving runner label. Sort the
        # inventory to avoid invalidation caused only by query ordering.
        if product == 'linux-host':
            commands += [['/opt/rh/gcc-toolset-14/root/usr/bin/gcc', '--version'],
                         ['/usr/local/cuda/bin/nvcc', '--version']]
            packages = output(['rpm', '-qa']).splitlines()
        else:
            commands += [['gcc', '--version'], ['qmake6', '-query', 'QT_VERSION']]
            packages = output(['dpkg-query', '-W', '-f=${Package}=${Version}\n']).splitlines()
    return {'architecture': platform.machine(), 'runner_image': os.environ.get('ImageVersion', ''),
            'os': Path('/etc/os-release').read_text() if product.startswith('linux-') else 'macOS',
            'packages': sorted(packages) if product.startswith('linux-') else [],
            'tools': [output(command) for command in commands]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('prepare', 'verify', 'seal'))
    parser.add_argument('--product', required=True, choices=PRODUCTS)
    parser.add_argument('--key')
    args = parser.parse_args()
    if args.product == 'macos-client':
        # Keep the already-qualified Mac Client cache/key format unchanged.
        command = [sys.executable, str(Path(__file__).with_name('cache-macos-client.py')), args.operation]
        if args.key:
            command += ['--key', args.key]
        os.execv(sys.executable, command)
    root = Path(os.environ['PLANK_SOURCE_ROOT']).resolve()
    deps = Path(os.environ['PLANK_DEP_ROOT']).resolve()
    if args.operation == 'prepare':
        if args.product == 'linux-host':
            subprocess.run(['git', '-C', str(root), 'submodule', 'update', '--init', 'apps/host/linux'], check=True)
            # The generated FFmpeg/x265 trees keep relative .git pointers to
            # these recursive sources. Restore requires them before patch checks.
            subprocess.run(['git', '-C', str(root / 'apps/host/linux'), 'submodule', 'update',
                            '--init', '--recursive', 'third-party/build-deps'], check=True)
        elif args.product == 'linux-client':
            subprocess.run(['git', '-C', str(root), 'submodule', 'update', '--init', 'apps/client'], check=True)
        key = fingerprint(root, deps, args.product, toolchain_inputs(args.product))
        if any(c in str(root) + str(deps) for c in ('\n', '\r')):
            raise ValueError('Invalid builder path')
        paths = '\n'.join(str(p) for p in cache_paths(root, deps, args.product))
        with open(os.environ['GITHUB_OUTPUT'], 'a') as result:
            result.write(f'key={key}\npaths<<PLANK_CACHE_PATHS\n{paths}\nPLANK_CACHE_PATHS\n')
        print('dependency_cache_key=' + key)
        return
    if not key_valid(args.key, args.product):
        raise ValueError('Exact dependency key required')
    if args.operation == 'verify':
        verify_receipt(root, deps, args.product, args.key)
    check_prepared(root, deps, args.product)
    if args.operation == 'seal':
        cache_paths(root, deps, args.product)[-1].write_text(
            json.dumps({'schema': 1, 'key': args.key}, sort_keys=True) + '\n')
    print('dependency_cache_' + args.operation + '=pass')


if __name__ == '__main__':
    main()
