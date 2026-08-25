#!/usr/bin/env python3
"""Generate the immutable EDIDs used by StationConnect virtual displays."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


# Qualified Dell U4021QW timing data. StationConnect replaces the identity
# descriptors while retaining its standard and CTA timing definitions.
BASE_EDID_HEX = """
00ffffffffffff0010ac0a424c313732
141f0104b54127783a52f5b04f42ab25
0f5054a54b00714f81008180a940b300
d1c0d100e1c04dd000a0f0703f803020
35008b882100001a000000ff00394c50
505438330a2020202020000000fc0044
454c4c20553430323151570a000000fd
001856198c3c010a20202020202001d6
020319f14c101f200514041312110302
01230907078301000008e80030f2705a
80b0588a008b882100001a565e00a0a0
a02950302035008b882100001a023a80
1871382d40582c45008b882100001e01
1d007251d01e206e2855008b88210000
1e000000000000000000000000000000
000000000000000000000000000000f2
"""


def eisa_manufacturer_id(name: str) -> bytes:
    """Return the packed two-byte EISA manufacturer identifier."""
    if len(name) != 3 or any(letter < "A" or letter > "Z" for letter in name):
        raise ValueError("EISA manufacturer name must contain three uppercase letters")
    value = ((ord(name[0]) - 64) << 10) | ((ord(name[1]) - 64) << 5) | (ord(name[2]) - 64)
    return value.to_bytes(2, byteorder="big")


def set_text_descriptor(edid: bytearray, offset: int, tag: int, text: str) -> None:
    """Replace one 18-byte EDID text descriptor."""
    encoded = (text + "\n").encode("ascii")
    if len(encoded) > 13:
        raise ValueError(f"EDID descriptor text is too long: {text!r}")
    edid[offset : offset + 18] = b"\x00\x00\x00" + bytes([tag, 0]) + encoded.ljust(13, b" ")


def build_edid(index: int) -> bytes:
    """Build one checksum-valid EDID with a stable StationConnect identity."""
    edid = bytearray.fromhex(BASE_EDID_HEX)
    if len(edid) != 256:
        raise ValueError(f"base EDID has {len(edid)} bytes instead of 256")
    if edid[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        raise ValueError("base EDID header is invalid")
    if any(sum(edid[offset : offset + 128]) & 0xFF for offset in range(0, len(edid), 128)):
        raise ValueError("base EDID checksum is invalid")

    edid[8:10] = eisa_manufacturer_id("INS")
    edid[10:12] = (0x5300 + index).to_bytes(2, byteorder="little")
    edid[12:16] = index.to_bytes(4, byteorder="little")
    edid[16] = 1
    edid[17] = 36
    set_text_descriptor(edid, 72, 0xFF, f"SCVIRT{index:06d}")
    set_text_descriptor(edid, 90, 0xFC, f"SC Virtual {index}")
    edid[127] = (-sum(edid[:127])) & 0xFF

    if any(sum(edid[offset : offset + 128]) & 0xFF for offset in range(0, len(edid), 128)):
        raise ValueError("generated EDID checksum is invalid")
    return bytes(edid)


def main() -> int:
    """Write the two package EDIDs and print their SHA-256 provenance."""
    parser = argparse.ArgumentParser()
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    for index in (1, 2):
        data = build_edid(index)
        output = args.output_directory / f"virtual-{index}.edid"
        output.write_bytes(data)
        print(f"{hashlib.sha256(data).hexdigest()}  {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
