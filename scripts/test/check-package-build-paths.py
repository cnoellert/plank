#!/usr/bin/env python3
"""Reject home-directory paths in release payloads without printing matched data."""
import argparse
from pathlib import Path
import re

# Includes C strings and DWARF, independent of executable format or stripping.
HOME_PATH = re.compile(rb'/(?:home|Users)/[^/\x00\s]+/')


def check(root):
    failures = []
    paths = [root] if root.is_file() else root.rglob('*')
    for path in paths:
        if path.is_symlink() or not path.is_file():
            continue
        if HOME_PATH.search(path.read_bytes()):
            # Counts only: a filename itself might contain sensitive information.
            failures.append(path)
    return len(failures)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('payload', type=Path)
    args = parser.parse_args()
    if not args.payload.exists():
        parser.error('payload is missing')
    failures = check(args.payload)
    print(f'package_build_path_gate={"FAIL" if failures else "pass"} files={failures}')
    raise SystemExit(bool(failures))
