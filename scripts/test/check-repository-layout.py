#!/usr/bin/env python3
"""Check first-party layout and relative documentation links without a toolchain."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def main():
    errors = []
    required = (
        'apps/host/linux', 'apps/host/macos', 'apps/client', 'apps/relay',
        'apps/wake-agent', 'scripts/build', 'scripts/package', 'scripts/test',
        'scripts/maintenance', 'packaging/host/linux', 'packaging/host/macos',
        'packaging/client/linux', 'packaging/relay/linux',
        'packaging/wake-agent/linux', 'docs/README.md', 'CONTRIBUTING.md',
    )
    for name in required:
        if not (ROOT / name).exists():
            errors.append('missing layout entry: ' + name)
    for section, expected in (
        ('host/sunshine-fork', 'apps/host/linux'),
        ('client/moonlight-qt-fork', 'apps/client'),
    ):
        actual = subprocess.check_output(
            ['git', 'config', '-f', str(ROOT / '.gitmodules'),
             'submodule.' + section + '.path'], text=True).strip()
        if actual != expected:
            errors.append('unexpected submodule path: ' + section)
    files = subprocess.check_output(
        ['git', '-C', str(ROOT), 'ls-files', '--cached', '--others',
         '--exclude-standard'], text=True).splitlines()
    for name in sorted(set(files)):
        path = ROOT / name
        if path.suffix not in ('.md', '.plan') or not path.is_file():
            continue
        for target in re.findall(r'\]\(([^\s)]+)\)', path.read_text()):
            if '://' in target or target.startswith(('#', '/', 'mailto:')):
                continue
            target = target.split('#', 1)[0]
            if target and not (path.parent / target).exists():
                errors.append(name + ': missing link target ' + target)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    print('repository_layout_and_documentation_links=pass')
    return 0


if __name__ == '__main__':
    sys.exit(main())
