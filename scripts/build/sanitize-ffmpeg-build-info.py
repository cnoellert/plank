#!/usr/bin/env python3
"""Remove local prefixes from FFmpeg's generated diagnostic configuration only."""
import argparse
from pathlib import Path
import re


def sanitize(path, roots):
    text = path.read_text()
    pattern = r'^#define FFMPEG_CONFIGURATION "[^\n]*"$'
    matches = list(re.finditer(pattern, text, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError('expected exactly one generated FFMPEG_CONFIGURATION definition')
    match = matches[0]
    value = match.group()
    for root in sorted(set(roots), key=len, reverse=True):
        if not root.startswith('/') or root == '/':
            raise ValueError('expected a non-root absolute build prefix')
        value = value.replace(root, '/build/dependencies')
    path.write_text(text[:match.start()] + value + text[match.end():])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('config', type=Path)
    parser.add_argument('roots', nargs='+')
    args = parser.parse_args()
    sanitize(args.config, args.roots)
