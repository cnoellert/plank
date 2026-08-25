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


# Deterministic 60 Hz timings. These are the complete
# StationConnect virtual-monitor allowlist. Keep the protocol, host parser,
# client bookmark UI, and display-preparation helper synchronized with it.
# Each tuple is:
# pixel clock MHz, h active/start/end/total, v active/start/end/total.
MODE_TIMINGS = {
    "1024x2160": (157.75, 1024, 1072, 1104, 1184, 2160, 2163, 2173, 2222),
    "1280x720": (63.75, 1280, 1328, 1360, 1440, 720, 723, 728, 741),
    "1280x1024": (90.75, 1280, 1328, 1360, 1440, 1024, 1027, 1034, 1054),
    "1280x2160": (191.75, 1280, 1328, 1360, 1440, 2160, 2163, 2173, 2222),
    "1920x1080": (138.50, 1920, 1968, 2000, 2080, 1080, 1083, 1088, 1111),
    "1920x1200": (154.00, 1920, 1968, 2000, 2080, 1200, 1203, 1209, 1235),
    "2560x1440": (241.50, 2560, 2608, 2640, 2720, 1440, 1443, 1448, 1481),
    "2560x1600": (268.50, 2560, 2608, 2640, 2720, 1600, 1603, 1609, 1646),
    "3440x1440": (319.75, 3440, 3488, 3520, 3600, 1440, 1443, 1453, 1481),
    "3840x1600": (394.75, 3840, 3888, 3920, 4000, 1600, 1603, 1613, 1646),
    "3840x2160": (533.00, 3840, 3888, 3920, 4000, 2160, 2163, 2168, 2222),
    # CTA-861 VIC 102. EDID 1.x detailed timings are limited to 4095 active
    # pixels, so this mode is advertised through the CTA video data block.
    "4096x2160": (594.00, 4096, 4184, 4272, 4400, 2160, 2168, 2178, 2250),
}

CTA_4096X2160P60_VIC = 102


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


def detailed_timing(mode: str) -> tuple[bytes, int, int]:
    """Encode one CVT-RB mode as an EDID detailed-timing descriptor."""
    if mode == "4096x2160":
        # The CTA extension below carries the requested cinema mode. Retain a
        # valid 3840x2160 base-block fallback instead of overflowing the
        # 12-bit EDID 1.x horizontal-active field.
        mode = "3840x2160"
    (clock_mhz, h_active, h_sync_start, h_sync_end, h_total,
     v_active, v_sync_start, v_sync_end, v_total) = MODE_TIMINGS[mode]
    h_blank = h_total - h_active
    v_blank = v_total - v_active
    h_sync_offset = h_sync_start - h_active
    h_sync_width = h_sync_end - h_sync_start
    v_sync_offset = v_sync_start - v_active
    v_sync_width = v_sync_end - v_sync_start

    # Give desktop software a plausible physical aspect without claiming a
    # particular commercial monitor size. The 1280x2160 Flame sidecar is
    # intentionally tall; all other presets use the same 600 mm width.
    h_size_mm = 320 if mode in ("1024x2160", "1280x2160") else 600
    v_size_mm = round(h_size_mm * v_active / h_active)
    descriptor = bytearray(18)
    descriptor[0:2] = round(clock_mhz * 100).to_bytes(2, "little")
    descriptor[2] = h_active & 0xFF
    descriptor[3] = h_blank & 0xFF
    descriptor[4] = ((h_active >> 8) & 0xF) << 4 | ((h_blank >> 8) & 0xF)
    descriptor[5] = v_active & 0xFF
    descriptor[6] = v_blank & 0xFF
    descriptor[7] = ((v_active >> 8) & 0xF) << 4 | ((v_blank >> 8) & 0xF)
    descriptor[8] = h_sync_offset & 0xFF
    descriptor[9] = h_sync_width & 0xFF
    descriptor[10] = (v_sync_offset & 0xF) << 4 | (v_sync_width & 0xF)
    descriptor[11] = (((h_sync_offset >> 8) & 0x3) << 6 |
                      ((h_sync_width >> 8) & 0x3) << 4 |
                      ((v_sync_offset >> 4) & 0x3) << 2 |
                      ((v_sync_width >> 4) & 0x3))
    descriptor[12] = h_size_mm & 0xFF
    descriptor[13] = v_size_mm & 0xFF
    descriptor[14] = ((h_size_mm >> 8) & 0xF) << 4 | ((v_size_mm >> 8) & 0xF)
    descriptor[17] = 0x1A  # digital separate sync, +HSync, -VSync
    return bytes(descriptor), h_size_mm, v_size_mm


def build_edid(index: int, mode: str) -> bytes:
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
    timing, h_size_mm, v_size_mm = detailed_timing(mode)
    edid[21] = min(255, round(h_size_mm / 10))
    edid[22] = min(255, round(v_size_mm / 10))
    edid[54:72] = timing
    set_text_descriptor(edid, 72, 0xFF, f"SCVIRT{index:06d}")
    set_text_descriptor(edid, 90, 0xFC, f"SC Virtual {index}")
    edid[127] = (-sum(edid[:127])) & 0xFF

    if mode == "4096x2160":
        # The base Dell CTA block begins with a 12-entry Video Data Block at
        # byte 132. Make CTA VIC 102 its native first entry. The Xorg NVIDIA
        # driver then publishes the standard 4096x2160 mode used by MetaModes.
        if edid[132] != 0x4C:
            raise ValueError("base EDID CTA video data block changed unexpectedly")
        edid[133] = 0x80 | CTA_4096X2160P60_VIC
        edid[255] = (-sum(edid[128:255])) & 0xFF

    if any(sum(edid[offset : offset + 128]) & 0xFF for offset in range(0, len(edid), 128)):
        raise ValueError("generated EDID checksum is invalid")
    return bytes(edid)


def main() -> int:
    """Write every head/mode EDID and print its SHA-256 provenance."""
    parser = argparse.ArgumentParser()
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    for index in (1, 2):
        for mode in MODE_TIMINGS:
            data = build_edid(index, mode)
            output = args.output_directory / f"virtual-{index}-{mode}.edid"
            output.write_bytes(data)
            print(f"{hashlib.sha256(data).hexdigest()}  {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
