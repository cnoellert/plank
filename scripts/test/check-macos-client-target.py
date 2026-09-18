#!/usr/bin/env python3
"""Verify the arm64 minimum OS of every Mach-O in a Client dependency/app tree."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess


MACHO_MAGIC = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
               b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
               b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def version(value):
    if not re.fullmatch(r'\d+(\.\d+){0,2}', value):
        raise ValueError('Invalid macOS version')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def check(root, target):
    ceiling = version(target)
    checked = 0
    failures = []
    for path in sorted(root.rglob('*')):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as handle:
            if handle.read(4) not in MACHO_MAGIC:
                continue
        checked += 1
        try:
            output = subprocess.check_output(
                ['xcrun', 'otool', '-arch', 'arm64', '-l', str(path)],
                text=True, stderr=subprocess.STDOUT)
            matches = re.findall(
                r'cmd LC_BUILD_VERSION\n.*?\bminos (\d+(?:\.\d+){0,2})\b|'
                r'cmd LC_VERSION_MIN_MACOSX\n.*?\bversion (\d+(?:\.\d+){0,2})\b',
                output, re.S)
            minimums = [a or b for a, b in matches]
            if not minimums or any(version(v) > ceiling for v in minimums):
                failures.append({'file': str(path.relative_to(root)),
                                 'minimums': minimums,
                                 'reason': 'Missing arm64 minimum or newer than target'})
        except subprocess.CalledProcessError:
            failures.append({'file': str(path.relative_to(root)), 'reason': 'otool failed'})
    plist = root / 'Contents/Info.plist'
    if plist.exists():
        with plist.open('rb') as handle:
            declared = plistlib.load(handle).get('LSMinimumSystemVersion', '')
        if declared != target:
            failures.append({'file': 'Contents/Info.plist', 'reason': 'Target mismatch'})
    if checked == 0:
        failures.append({'reason': 'No Mach-O binaries checked'})
    return {'target': target, 'architecture': 'arm64', 'checked': checked,
            'passed': not failures, 'failures': failures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--target', required=True)
    args = parser.parse_args()
    result = check(args.root, args.target)
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
