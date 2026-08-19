# Upstream Baseline — 2026-08-19

The pinned Sunshine `v2026.817.185037` source was configured on the Rocky 9.7
Ada host with X11 and CUDA enabled. Unrelated DRM, VA-API, Vulkan, Wayland,
KWin, portal, and tray targets were disabled for this focused baseline.

Build-only dependencies were staged under `/tmp`; no RPMs, NVIDIA driver
components, Xorg configuration, or system libraries were changed. CMake
successfully configured with GCC Toolset 14 and CUDA 13.1. The build compiled
Sunshine, its CUDA conversion kernel, X11 capture path, vendored
moonlight-common-c, Web UI, and test objects through 100%.

Final linking is blocked by Sunshine's pinned prebuilt x265 archive, which
references `_ZGVbN2v_log2`; Rocky's glibc 2.34 `libmvec` does not export that
symbol. This is an upstream binary-dependency compatibility issue, not a
failure of NvFBC, CUDA, NVENC, or the StationConnect qualification probes.
Resolve it by rebuilding Sunshine's pinned FFmpeg dependency bundle on a
Rocky-compatible baseline or by producing the host package in a compatible
RHEL/Rocky build environment. Do not replace workstation glibc.

Moonlight-Qt `v6.1.0` and all pinned nested dependencies were initialized on
the dedicated Ubuntu 26.04 NUC. The release target built successfully against
Qt 6.10.2, FFmpeg 8.0.1, VA-API 1.23, DRM, EGL, and libplacebo 7.360.0. A
five-second launch in the real Wayland session selected the Intel iHD driver,
Moonlight's VA-API accelerated renderer, and mailbox Vulkan presentation. Its
built-in HEVC Main10 test selected FFmpeg's `vaapi` path and a P010 surface.

The upstream client baseline therefore works without a custom renderer. The
remaining color-path delta is specific: for a matrix-coefficient-0 HEVC Rext
4:4:4 stream, FFmpeg currently reports `gbrp10le` and misses this hardware
path. StationConnect must preserve hardware selection using the driver's
Y410/XV30 surface and apply the identity channel interpretation at presentation.
