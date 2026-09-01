# Hardware Qualification

Phase 0 starts with probes that prove target hardware behavior before either
upstream application is forked. Run the host inventory on the Rocky 9.7
workstation from the repository root:

- [Ada `hardware-test-host` qualification](rocky-hardware-test-host-2026-08-19.md)
- [Ampere/Turing capability matrix](nvidia-host-matrix-2026-08-19.md)
- [Intel NUC client qualification](intel-nuc-client-qualification.md)
- [End-to-end audio qualification](../audio-qualification.md)
- [Current RGS session-transition reference](reference-host-rgs-session-transition-2026-08-22.md)

```bash
./scripts/run-host-qualification.sh
```

The command builds the probes, runs a ten-second 60 fps X11-to-CUDA capture gate
through NvFBC, and writes
`artifacts/qualification/reports/qualification-report.md`. It also performs a
real 2160p60 NVENC HEVC FRExt 10-bit 4:4:4 encode with periodic and single-slice
intra-refresh enabled; it is not merely an FFmpeg option inventory. Set
`NVFBC_SDK_ROOT` if CMake cannot find the NVIDIA Capture SDK header.

NvFBC 1.9 exposes BGRA8888 and other 8-bit formats only. The report therefore
labels this stable capture path as 8-bit-source/up-converted even when the
local Xorg desktop has depth 30. Do not modify Xorg, replace the NVIDIA DDX, or
claim native 10-bit capture to make this gate pass.

DRM/KMS is retained as inventory. Override its primary node with
`PLANK_DRM_DEVICE=/dev/dri/card1` when required. The account running the probe
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
bounded forced IDR in separate streams. The invalidation run also writes a
synchronized no-loss reference. Copy the streams to the NUC, run
`probe-intel-recovery-decode.sh` for continuity, then compare every aligned
decoded Y410 frame with:

```bash
./scripts/probe-intel-recovery-pixels.sh \
  plank-recovery-ref-invalidate-reference.hevc \
  plank-recovery-ref-invalidate.hevc 180 600 120
```

Transport FEC remains a separate live-session gate.

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

Set the qualification build location once for direct probe invocations:

```bash
qualification_build=${PLANK_BUILD_DIR:-"${PLANK_WORK_ROOT:-${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work}/qualification"}
```

Run `sudo "$qualification_build/plank-probe-uhid" --self-test-mouse` to verify
the UHID transport itself. Then run `./scripts/probe-wacom-uhid.sh` to create an
eight-second virtual copy from the physical Wacom interface descriptor and
check whether `hid-wacom` exposes input devices. The Wacom probe deliberately
declines feature/output reports; bidirectional report forwarding is a later
test and may be required before the device binds.

Use `--generic` to substitute a community USB vendor/product ID while retaining
the supplied report descriptor. This is a control for UHID and generic HID
parsing only; it does not qualify the Wacom driver or preserve production
device identity:

```bash
sudo "$qualification_build/plank-probe-uhid" --generic \
  /sys/class/hidraw/hidraw2/device/report_descriptor
```

For a non-`0317` Wacom descriptor, pass its hexadecimal product ID so the
kernel probes the correct model table. Supply all HID-interface descriptors in
one invocation so they share physical identity, for example:

```bash
sudo "$qualification_build/plank-probe-uhid" --product 0357 \
  /sys/class/hidraw/hidraw4/device/report_descriptor \
  /sys/class/hidraw/hidraw6/device/report_descriptor
```

For client-side exact raw-HID forwarding, install
`packaging/udev/70-plank-client-wacom.rules` on the Ubuntu client and
reload udev before attaching the tablet. The rule grants only the active local
session access to Wacom input and hidraw interfaces; it does not make those
devices globally writable. PLANK grabs the complete tablet group while
its stream window has focus and releases it on focus loss or disconnect.
