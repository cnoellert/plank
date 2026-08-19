# NVIDIA Host Capability Matrix — 2026-08-19

These read-only results were collected on idle Rocky Linux 9.7 GDM sessions.
They establish API capabilities only; they are not capture or 60 fps performance
results because no fullscreen workload was available.

| Host | GPU | Architecture | Display active | NVENC engines |
| --- | --- | --- | --- | --- |
| `additional-hardware-host` | RTX A5000, 24 GB | Ampere GA102 | Yes | 1 |
| `headless-test-host` | RTX A5500, 24 GB | Ampere GA102 | No | 1 |
| `secondary-hardware-host` | Quadro RTX 8000, 48 GB | Turing TU102 | Yes | 1 |

All three use NVIDIA driver 580.159.04 and report NVENC API 13.0. The repository
`connect-probe-nvenc` capability query passed on every host:

- HEVC Range Extensions profile and 10-bit 4:4:4 input are supported.
- Intra refresh, single-slice intra refresh, and reference invalidation are
  supported.
- Maximum HEVC encode dimensions are 8192x8192.
- HEVC 10-bit 4:2:2 encode is not supported.

Each host has the NvFBC and NVENC runtime libraries, NVIDIA Xorg, and FFmpeg with
`hevc_nvenc`. The next gate is a complete 9,000-frame NvFBC-to-NVENC run with
real changing 2160p60 content. Ampere and Turing have only one reported encoder
engine, so split-frame encoding is unavailable; they must meet the 16.67 ms
frame budget unsplit.
