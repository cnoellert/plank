#!/usr/bin/env python3
"""Reject home-directory paths in release payloads without printing matched data."""
import argparse
from pathlib import Path
import re

# Includes C strings and DWARF, independent of executable format or stripping.
HOME_PATH = re.compile(rb'/(?:home|Users)/[^/\x00\s]+/')
# Reviewed literals in the pinned official Qt 6.10.2 macOS archives, not PLANK
# operator paths. Restrict to exact strings in the exact framework payloads.
UPSTREAM_QT_PATHS = {
    '/Contents/Frameworks/QtQuick.framework/Versions/A/QtQuick': (
        b'/Users/qt/work/qt/qtdeclarative/src/quick/designer/qquickdesignersupport.cpp',),
    '/Contents/Frameworks/QtWidgets.framework/Versions/A/QtWidgets': (
        b'/Users/qt/work/qt/qtbase/src/widgets/widgets/qdatetimeedit.cpp',
        b'/Users/qt/work/qt/qtbase/src/widgets/widgets/qabstractspinbox.cpp'),
}


def check(root):
    failures = []
    paths = [root] if root.is_file() else root.rglob('*')
    for path in paths:
        if path.is_symlink() or not path.is_file():
            continue
        data = path.read_bytes()
        allowed = next((values for suffix, values in UPSTREAM_QT_PATHS.items()
                        if path.as_posix().endswith(suffix)), ())
        if any(not any(data.startswith(value + b'\0', match.start()) for value in allowed)
               for match in HOME_PATH.finditer(data)):
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
