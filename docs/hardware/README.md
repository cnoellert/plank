# Hardware Qualification

Phase 0 starts with probes that prove target hardware behavior before either
upstream application is forked. Run the host inventory on the Rocky 9.7
workstation from the repository root:

- [Ada `hardware-test-host` qualification](rocky-hardware-test-host-2026-08-19.md)
- [Ampere/Turing capability matrix](nvidia-host-matrix-2026-08-19.md)
- [Intel NUC client qualification](intel-nuc-client-qualification.md)

```bash
./scripts/run-host-qualification.sh
```

The command builds the probes, runs a ten-second 60 fps X11-to-CUDA capture gate
through NvFBC, and writes `qualification-report.md`. It also performs a
real 2160p60 NVENC HEVC FRExt 10-bit 4:4:4 encode with periodic and single-slice
intra-refresh enabled; it is not merely an FFmpeg option inventory. Set
`NVFBC_SDK_ROOT` if CMake cannot find the NVIDIA Capture SDK header.

NvFBC 1.9 exposes BGRA8888 and other 8-bit formats only. The report therefore
labels this stable capture path as 8-bit-source/up-converted even when the
local Xorg desktop has depth 30. Do not modify Xorg, replace the NVIDIA DDX, or
claim native 10-bit capture to make this gate pass.

DRM/KMS is retained as inventory. Override its primary node with
`CONNECT_DRM_DEVICE=/dev/dri/card1` when required. The account running the probe
must be able to open the DRM primary node; render-node access alone cannot
enumerate connectors, CRTCs, and planes.

An XR30, AR30, XB30, or AB30 framebuffer is reported as native 10-bit RGB when
public KMS scanout exists. This does not change NvFBC's 8-bit output contract.

The FFmpeg encode proves the requested profile, pixel format, and basic intra
refresh initialization. A later direct NVENC SDK probe must still query exact
capability flags, test reference-picture invalidation, measure refresh-wave
bitrate, and exercise recovery after injected loss.

The Intel client probes use GStreamer `vah265dec` because FFmpeg 8.0.1 silently
falls back to software for the full-range GBR identity stream. The DMA-BUF probe
validates Y410 export, XR30 RGB-identity sampling, and exact pixel values without
mapping decoded pixels to the CPU. The Wayland probe separately validates a
fullscreen 10-bit EGL surface and compositor pacing. The integrated client probe
uses `wp_presentation` hardware timestamps to measure each real decoded frame
through fullscreen scanout with a bounded queue. The guarded direct-KMS probe
separates fixed-refresh scanout timing from compositor behavior; it interrupts
the graphical session and must be run remotely.

With real changing content already fullscreen on the host, generate the two
controlled-loss recovery vectors with:

```bash
./scripts/run-video-recovery-qualification.sh
```

This omits one complete access unit, then tests reference invalidation and a
bounded forced IDR in separate streams. Copy both streams to the NUC and run
`probe-intel-recovery-decode.sh` there. These probes establish encoder action
and decoder continuity; transport FEC and clean-pixel recovery remain separate
gates.

The generic modesetting and direct-KMS scripts below are historical diagnostic
controls, not production capture candidates. They interrupt the graphical
session and are unnecessary for routine qualification:

```bash
./scripts/probe-xorg-modesetting-kms.sh --confirm-display-outage
```

This deliberately stops GDM, starts a temporary depth-30 Xorg server, probes
its live scanout, and restores GDM through an exit trap. Run it only from a
remote shell or another session that survives the graphical-session outage.
Use `--accel=none` only as a control test when glamor fails; the resulting
shadow framebuffer is not an acceptable production capture path.

To test the NVIDIA driver's advertised `XB30` scanout directly, without Xorg:

```bash
./scripts/probe-direct-kms-xb30.sh --confirm-display-outage
```

This also stops and restores GDM. It displays a short 10-bit test pattern,
verifies the selected framebuffer format, exports it as DMA-BUF, and imports
that descriptor into EGL without reading the image back through the CPU.

The standard host report also inventories attached Wacom event capabilities
and hashes every physical Wacom HID report descriptor. It does not generate
input events; run application-level pen tests separately.

Run `sudo ./build/qualification/connect-probe-uhid --self-test-mouse` to verify
the UHID transport itself. Then run `./scripts/probe-wacom-uhid.sh` to create an
eight-second virtual copy from the physical Wacom interface descriptor and
check whether `hid-wacom` exposes input devices. The Wacom probe deliberately
declines feature/output reports; bidirectional report forwarding is a later
test and may be required before the device binds.
