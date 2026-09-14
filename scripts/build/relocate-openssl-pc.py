#!/usr/bin/env python3
"""Relocate staged OpenSSL development metadata, never runtime defaults."""
from pathlib import Path
import sys

prefix, configured = sys.argv[1:]
for name in ('libcrypto', 'libssl', 'openssl'):
    path = Path(prefix) / 'lib/pkgconfig' / (name + '.pc')
    text = path.read_text()
    if text.count('prefix=' + configured + '\n') != 1:
        raise SystemExit('unexpected OpenSSL pkg-config prefix')
    path.write_text(text.replace(configured, prefix))
