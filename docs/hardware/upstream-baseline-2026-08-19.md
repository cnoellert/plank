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

Moonlight-Qt `v6.1.0` and all pinned nested dependencies were initialized.
A native client build awaits a Qt/FFmpeg development environment on the
dedicated Ubuntu NUC; no client packages were installed during this run.
