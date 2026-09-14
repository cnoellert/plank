#!/usr/bin/env python3
"""Opt in one checkout without replacing an existing hook configuration."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    if not shutil.which('gitleaks'):
        sys.exit('Install Gitleaks first; see docs/security/private-information.md.')
    if Path(subprocess.check_output(['git', 'rev-parse', '--show-toplevel'], text=True).strip()).resolve() != ROOT:
        sys.exit('Run this installer from the root checkout containing the hooks.')
    configured = subprocess.run(['git', 'config', '--get', 'core.hooksPath'], capture_output=True, text=True)
    if configured.returncode not in (0, 1):
        sys.exit('Could not read hook configuration; nothing changed.')
    if configured.returncode == 0 and configured.stdout.strip() != '.githooks':
        sys.exit('An existing hook configuration is present; integrate it explicitly instead of overwriting it.')
    default_hooks = Path(subprocess.check_output(['git', 'rev-parse', '--git-path', 'hooks'], text=True).strip())
    if configured.returncode == 1 and default_hooks.exists():
        if any(p.is_file() and not p.name.endswith('.sample') for p in default_hooks.iterdir()):
            sys.exit('Existing default hooks found; integrate them explicitly instead of bypassing them.')
    for name in ('pre-commit', 'commit-msg'):
        if not os.access(ROOT / '.githooks' / name, os.X_OK):
            sys.exit('Hook is not executable; restore its tracked executable mode.')
    subprocess.run(['git', 'config', '--local', 'core.hooksPath', '.githooks'], check=True)
    print('PLANK pre-commit and commit-msg checks enabled for this local repository.')


if __name__ == '__main__':
    main()
