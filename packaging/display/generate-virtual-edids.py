#!/usr/bin/env python3
"""Generate the immutable EDIDs used by PLANK virtual displays."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


# Qualified Dell U4021QW base timing data. PLANK replaces the
# identity and detailed timings. The generated EDID is deliberately limited
# to 384 bytes because Mutter 40 reads at most 400 bytes from XRandR; a longer
# property is truncated to a non-128-byte length and rejected as unknown.
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
# PLANK virtual-monitor allowlist. Keep the protocol, host parser,
# client bookmark UI, and display-preparation helper synchronized with it.
# Each tuple is:
# pixel clock MHz, h active/start/end/total, v active/start/end/total.
MODE_TIMINGS = {
    "1024x2160": (157.53, 1024, 1072, 1104, 1180, 2160, 2163, 2173, 2225),
    "1280x2160": (192.24, 1280, 1328, 1360, 1440, 2160, 2163, 2173, 2225),
    "1920x1080": (139.86, 1920, 1968, 2000, 2100, 1080, 1083, 1088, 1110),
    "1920x1200": (155.61, 1920, 1968, 2000, 2100, 1200, 1203, 1209, 1235),
    "2560x1440": (241.98, 2560, 2608, 2640, 2725, 1440, 1443, 1448, 1480),
    "2560x1600": (269.28, 2560, 2608, 2640, 2720, 1600, 1603, 1609, 1650),
    "2560x2160": (363.12, 2560, 2608, 2640, 2720, 2160, 2163, 2173, 2225),
    "3440x1440": (319.68, 3440, 3488, 3520, 3600, 1440, 1443, 1453, 1480),
    "3840x1600": (395.04, 3840, 3888, 3920, 4000, 1600, 1603, 1613, 1646),
    "3840x2160": (533.28, 3840, 3888, 3920, 4000, 2160, 2163, 2168, 2222),
    # CTA-861 VIC 102. EDID 1.x detailed timings are limited to 4095 active
    # pixels, so this mode is advertised through the CTA video data block.
    "4096x2160": (594.00, 4096, 4184, 4272, 4400, 2160, 2168, 2178, 2250),
    "5120x2160": (742.50, 5120, 5280, 5376, 5500, 2160, 2168, 2178, 2250),
}

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
    if MODE_TIMINGS[mode][1] > 4095:
        # DisplayID below carries the requested wide mode. Retain a
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

    # These are virtual outputs, not physical panels. Mutter recognizes
    # 160x90 mm as an aspect-ratio marker, avoids deriving a misleading DPI,
    # and uses the EDID product identity in its display name.
    h_size_mm = 160
    v_size_mm = 90
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


def displayid_timing(mode: str, preferred: bool) -> bytes:
    """Encode one DisplayID 1.3 Type I detailed timing descriptor."""
    (clock_mhz, h_active, h_sync_start, h_sync_end, h_total,
     v_active, v_sync_start, v_sync_end, v_total) = MODE_TIMINGS[mode]
    descriptor = bytearray(20)
    descriptor[0:3] = (round(clock_mhz * 100) - 1).to_bytes(3, "little")
    descriptor[3] = 0x08 | (0x80 if preferred else 0)
    descriptor[4:6] = (h_active - 1).to_bytes(2, "little")
    descriptor[6:8] = (h_total - h_active - 1).to_bytes(2, "little")
    descriptor[8:10] = ((h_sync_start - h_active - 1) | 0x8000).to_bytes(2, "little")
    descriptor[10:12] = (h_sync_end - h_sync_start - 1).to_bytes(2, "little")
    descriptor[12:14] = (v_active - 1).to_bytes(2, "little")
    descriptor[14:16] = (v_total - v_active - 1).to_bytes(2, "little")
    descriptor[16:18] = ((v_sync_start - v_active - 1) | 0x8000).to_bytes(2, "little")
    descriptor[18:20] = (v_sync_end - v_sync_start - 1).to_bytes(2, "little")
    return bytes(descriptor)


def base_timing_modes(preferred_mode: str) -> list[str]:
    """Choose three exact timings for the base block, preferred first."""
    if MODE_TIMINGS[preferred_mode][1] > 4095:
        # EDID 1.x cannot represent more than 4095 active pixels. DisplayID marks it
        # preferred; these are conservative exact-60 base fallbacks.
        return ["3840x2160", "1920x1080", "1280x2160"]

    modes = [preferred_mode]
    for fallback in ("1920x1080", "1280x2160", "3840x2160"):
        if fallback not in modes:
            modes.append(fallback)
        if len(modes) == 3:
            break
    return modes


def displayid_timing_extensions(modes: list[str], preferred_mode: str) -> list[bytes]:
    """Encode the remaining exact timings in two DisplayID sections."""
    if not 6 <= len(modes) <= 10:
        raise ValueError("six to ten DisplayID timings are required")
    chunks = [modes[offset : offset + 5] for offset in range(0, len(modes), 5)]
    extensions = []
    for section_index, chunk in enumerate(chunks):
        extension = bytearray(128)
        extension[0] = 0x70  # DisplayID extension tag
        extension[1] = 0x13  # DisplayID version 1.3
        extension[2] = 3 + 20 * len(chunk)
        # Product type and continuation count belong only to the first
        # DisplayID section. Continuation sections carry zero in both fields.
        extension[3] = 0x03 if section_index == 0 else 0
        extension[4] = len(chunks) - 1 if section_index == 0 else 0
        extension[5:8] = bytes((0x03, 0x00, 20 * len(chunk)))
        descriptor_offset = 8
        for mode in chunk:
            extension[descriptor_offset : descriptor_offset + 20] = displayid_timing(
                mode, mode == preferred_mode
            )
            descriptor_offset += 20
        extension[descriptor_offset] = (-sum(extension[1:descriptor_offset])) & 0xFF
        extension[127] = (-sum(extension[:127])) & 0xFF
        extensions.append(bytes(extension))
    return extensions


def validate_exact_refresh_rates() -> None:
    """Require every qualified timing to be exactly 60 Hz after encoding."""
    for mode, timing in MODE_TIMINGS.items():
        clock_mhz, _, _, _, h_total, _, _, _, v_total = timing
        encoded_clock_hz = round(clock_mhz * 100) * 10_000
        if encoded_clock_hz != h_total * v_total * 60:
            raise ValueError(f"qualified mode is not exactly 60 Hz: {mode}")


def validate_mode_pool(edid: bytes, base_modes: list[str], preferred_mode: str) -> None:
    """Verify one complete exact-60 pool and one preferred timing."""
    advertised = list(base_modes)
    preferred = []
    if edid[24] & 0x02:
        preferred.append(base_modes[0])
    for offset in range(128, len(edid), 128):
        extension = edid[offset : offset + 128]
        if (extension[0] != 0x70 or extension[5:7] != bytes((0x03, 0x00)) or
                extension[7] == 0 or extension[7] % 20 != 0):
            raise ValueError("generated DisplayID timing section is invalid")
        for descriptor_offset in range(8, 8 + extension[7], 20):
            descriptor = extension[descriptor_offset : descriptor_offset + 20]
            resolution = (
                int.from_bytes(descriptor[4:6], "little") + 1,
                int.from_bytes(descriptor[12:14], "little") + 1,
            )
            mode = next((name for name, timing in MODE_TIMINGS.items()
                         if resolution == (timing[1], timing[5])), None)
            if mode is None:
                raise ValueError("generated DisplayID timing is not qualified")
            advertised.append(mode)
            if descriptor[3] & 0x80:
                preferred.append(mode)
    if (len(advertised) != len(MODE_TIMINGS) or
            set(advertised) != set(MODE_TIMINGS) or
            preferred != [preferred_mode]):
        raise ValueError("generated mode pool or preferred timing is invalid")


def build_edid(index: int, mode: str) -> bytes:
    """Build one checksum-valid EDID with a stable PLANK identity."""
    validate_exact_refresh_rates()
    edid = bytearray.fromhex(BASE_EDID_HEX)[:128]
    if len(edid) != 128:
        raise ValueError(f"base EDID has {len(edid)} bytes instead of 128")
    if edid[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        raise ValueError("base EDID header is invalid")
    if sum(edid) & 0xFF:
        raise ValueError("base EDID checksum is invalid")

    # PLK is the stable private PLANK Virtual manufacturer identity.
    edid[8:10] = eisa_manufacturer_id("PLK")
    edid[10:12] = (0x5300 + index).to_bytes(2, byteorder="little")
    edid[12:16] = index.to_bytes(4, byteorder="little")
    edid[16] = 1
    edid[17] = 36
    base_modes = base_timing_modes(mode)
    timing, h_size_mm, v_size_mm = detailed_timing(base_modes[0])
    edid[21] = min(255, round(h_size_mm / 10))
    edid[22] = min(255, round(v_size_mm / 10))
    if MODE_TIMINGS[mode][1] > 4095:
        # The preferred Type I DisplayID timing is authoritative.
        edid[24] &= ~0x02
    edid[54:72] = timing
    edid[72:90] = detailed_timing(base_modes[1])[0]
    edid[90:108] = detailed_timing(base_modes[2])[0]
    set_text_descriptor(edid, 108, 0xFC, f"Display {index}")

    displayid_modes = [candidate for candidate in MODE_TIMINGS
                       if candidate not in base_modes]
    displayid_extensions = displayid_timing_extensions(displayid_modes, mode)
    edid[126] = len(displayid_extensions)
    edid[127] = (-sum(edid[:127])) & 0xFF
    edid.extend(b"".join(displayid_extensions))

    if any(sum(edid[offset : offset + 128]) & 0xFF for offset in range(0, len(edid), 128)):
        raise ValueError("generated EDID checksum is invalid")
    if len(edid) != 384:
        raise ValueError("generated EDID exceeds Mutter's complete-read limit")
    validate_mode_pool(edid, base_modes, mode)
    return bytes(edid)


def main() -> int:
    """Write one complete, canonical EDID per virtual output."""
    parser = argparse.ArgumentParser()
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    args.output_directory.mkdir(parents=True, exist_ok=True)

    for index in (1, 2):
        data = build_edid(index, "1920x1080")
        output = args.output_directory / f"virtual-{index}.edid"
        output.write_bytes(data)
        print(f"{hashlib.sha256(data).hexdigest()}  {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
