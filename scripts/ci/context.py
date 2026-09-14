#!/usr/bin/env python3
"""Select safe, explicit candidate paths and versions on an ephemeral runner."""
import hashlib
import os
from pathlib import Path
import re
import subprocess


def branch_name(ref):
    if not ref:
        raise ValueError('Missing build ref')
    normalized = re.sub('[^a-z0-9]+', '-', ref.lower()).strip('-')
    if not normalized:
        raise ValueError('Empty normalized build ref')
    if normalized != ref:
        normalized += '-' + hashlib.sha256(ref.encode()).hexdigest()[:8]
    return normalized


if __name__ == '__main__':
    root = Path(os.environ['GITHUB_WORKSPACE']).resolve()
    base = Path(os.environ['RUNNER_TEMP']).resolve() / 'plank-ci'
    assert not base.exists(), 'CI scratch root already exists'
    sha = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    assert sha == os.environ['GITHUB_SHA']
    base.mkdir()
    branch = branch_name(os.environ['BUILD_REF'])
    values = {
        'PLANK_CANONICAL_ROOT': str(root), 'PLANK_SOURCE_ROOT': str(base/'source'),
        'PLANK_WORK_ROOT': str(base/'work'), 'PLANK_DEP_ROOT': str(base/'deps'),
        'PLANK_ARTIFACT_ROOT': str(base/'packages'), 'PLANK_PACKAGE_ROOT': str(base/'packages'),
        'PLANK_RUSTUP_ROOT': str(base/'deps/rustup'), 'PLANK_CARGO_ROOT': str(base/'deps/cargo'),
        'PLANK_BUILD_BRANCH': branch,
    }
    for value in values.values():
        assert '\n' not in value and '\r' not in value
    with open(os.environ['GITHUB_ENV'], 'a') as f:
        for key, value in values.items():
            f.write(f'{key}={value}\n')
    subprocess.run(['git', '-C', str(root), 'worktree', 'add', '--detach', values['PLANK_SOURCE_ROOT'], sha], check=True)
    print('Clean CI worktree selected; branch qualifier:', branch)
