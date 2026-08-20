# Rocky Host `hardware-test-host` — 2026-08-19

## Baseline

- OS: Rocky Linux 9.7, kernel `5.14.0-611.55.1.el9_7.x86_64`
- GPU: NVIDIA RTX 6000 Ada Generation
- Driver: NVIDIA open kernel module `580.159.04`
- Display server: Xorg on GDM `seat0`
- Root window: 5120x2160, depth 30
- DRM primary node: `/dev/dri/card0` (`nvidia-drm`)

## Results

| Gate | Result | Evidence |
| --- | --- | --- |
| Xorg 30-bit source | Pass | `xdpyinfo` reports root depth 30. |
| NvFBC X11 availability | Pass | API 1.9 sees the 5120x2160 screen and both RandR outputs. |
| NvFBC CUDA capture | Pass | Live 5120x2160 `BGRA8888` frames remain in CUDA device memory with no CPU readback. |
| NvFBC 60 fps animated capture | Pass | With looping content visible, all 600 calls returned new frames at 60.00 fps; p95 was 49 us, maximum 2.497 ms, and no 16.67 ms deadlines were missed. NvFBC reported 23 intervening generations because its 16 ms producer timer runs at 62.5 Hz. |
| Native 10-bit NvFBC source | Unsupported, non-blocking | NvFBC 1.9 exposes only 8-bit RGB/YUV output formats, including native `BGRA8888`; the approved baseline is labeled 8-bit-source/up-converted. |
| HEVC Rext 10-bit 4:4:4 encode | Pass | The integrated 600-frame stream decodes without error; `ffprobe` reports `Rext`, `gbrp10le`, full-range GBR identity signaling, sRGB transfer, and BT.709 primaries. |
| Live Sunshine/Moonlight identity session | Functional pass; pacing gate pending | The NUC negotiated format `0x800`, hardware-decoded to Y410, imported the Y410/XR30 alias through EGL, and sustained approximately 60 fps. Instrumentation traced the only drops in a 7:27 soak to two startup render-queue catch-up events; sustained playback had none. |
| NVIDIA driver/build-deps compatibility | Fixed in fork | Driver 580 exposes NVENC API 13.0. The StationConnect build-deps fork pins `nv-codec-headers` to API 13.0 and prevents GCC from introducing a glibc vector-math ABI into x265 that Rocky 9 does not provide. |
| Synthetic animated 2160p60 pipeline | Pass, marginal | The enforced rerun sustained 60.05 fps with zero submission misses and 15.959 ms p95, but its 16.862 ms p99 failed the stricter robustness gate. P95 headroom was only 0.708 ms. |
| Full looping production workload | Pass | The instrumented 150-second loop encoded 9,000 frames at 60.01 fps with 8,999 new captures, zero misses, 14.645 ms p95, 15.041 ms p99, and 2.022 ms p95 headroom. |
| Real-workload SFE A/B | Auto required on Ada | Matched 9,000-frame runs measured 14.512 ms p95 and 14.939 ms p99 with driver-auto, versus 17.419 ms p95 and 17.752 ms p99 with SFE disabled. Both decoded without error; only auto met the 16.67 ms budget. |
| Fullscreen-footage SFE A/B | Auto required on Ada | With footage filling the 3840x2160 capture output, auto measured 14.290 ms p95 and 2.377 ms headroom. Disabled measured 17.321 ms p95 and failed the budget by 0.654 ms. Both sustained 60.00 fps with no deadline misses. |
| NVENC Ultra-Low-Latency tuning | No material gain | A matched 150-second ULL run sustained 60.00 fps with zero misses and measured 14.644 ms p95 and 15.013 ms p99. The 1 us p95 difference from LL is noise, so LL remains the default. |
| NVENC 8 ms component target | Fail, non-blocking | NVENC completion p95 was 14.328 ms on the full loop. Its blocking bitstream-lock wait was 14.249 ms p95, while mapping, submission, and output-worker dispatch totaled under 0.1 ms at p95. The tail is inside NVIDIA's encode/completion path. |
| HEVC 10-bit 4:2:2 encode | Unsupported | Live capability query returns `caps_yuv422_encode=0`; NVIDIA added HEVC 4:2:2 encode after the Turing/Ampere/Ada fleet. |
| Intra-refresh latency matrix | Pass; retain 60/30 single-slice | Seven full-loop profiles covered refresh disabled and counts 30/45/59 with single- and multi-slice refresh. Pipeline p95 ranged only from 14.404 to 14.620 ms; disabling refresh gained just 0.108 ms over baseline. Every stream decoded all 9,000 frames. |
| Controlled-loss recovery continuity | Pass; pixel/FEC gate pending | Separate 600-frame real-content runs dropped access unit 180. Reference invalidation accepted timestamp 180 two frames later; the emergency path forced an IDR with VPS/SPS/PPS at frame 182. Both wrote exactly 599 pictures, retained the host robustness gate, and decoded all 599 pictures through Intel VA-API. |
| DRM KMS API enablement | Pass | After reboot, `nvidia_drm.modeset=Y`; atomic modesetting and universal planes are exposed. |
| Active KMS scanout enumeration | Fail | All four DRM CRTCs and twelve planes report framebuffer ID 0 while NVIDIA Xorg drives two displays. |
| XR30/AR30 framebuffer and DMA-BUF export | Blocked | The NVIDIA Xorg session exposes no active scanout framebuffer through DRM KMS. |
| Direct native 10-bit KMS scanout | Pass | A standalone DRM master scanned out `XB30` at 3840x2160/60. |
| Native 10-bit DMA-BUF export/import | Pass | The `XB30` buffer exported successfully and imported into NVIDIA EGL 1.5 without CPU readback. |
| Direct NVENC required capabilities | Pass | API 13.0 exposes FRExt, 10-bit 4:4:4 input, intra refresh, reference invalidation, and single-slice intra refresh. |
| Physical Wacom discovery | Pass | USB `056a:0317` Intuos Pro L exposes pen, pad, touch, and two raw HID interfaces. |
| Generic UHID transport | Pass | A temporary generic mouse receives `UHID_START` and binds through the host kernel. |
| Wacom UHID binding | Blocked | The physical interface descriptor alone does not reach `UHID_START`; multi-interface identity and feature-report forwarding must be implemented. |
| PAM/SSSD account policy | Pass | Root and `gdm` are rejected; authorized SSSD accounts `operator` and `testartist` pass account management. |
| PAM password/session conversation | Pending | Requires secure interactive tests for valid and invalid credentials. |

## Production Capture Decision

`nvidia_drm.modeset=1` was added to every installed Rocky boot entry with
`grubby` and verified active after reboot on 2026-08-19. The active
`/etc/X11/xorg.conf` selects `DefaultDepth 30`, and Xorg confirms RGB 10:10:10,
but it uses NVIDIA's proprietary X driver path rather than an active public DRM
KMS scanout. Debugfs independently confirms every DRM CRTC is inactive.

Production capture uses the NVIDIA-supported NvFBC X11 backend and leaves the
qualified Xorg/DDX/GLX stack untouched. The initial live test selected the X11
backend, enumerated `DP-1` and `DP-2`, and successfully created a CUDA capture
session. NvFBC enumerates the narrow `DP-1` scopes monitor as output `0` even
though Xorg marks `DP-2` primary. Production Sunshine must therefore set
`output_name = 1` on this workstation and verify the resulting 3840x2160,
offset-0 capture; its default selected the scopes monitor. Rerun the
qualification report with:

```bash
./scripts/run-host-qualification.sh
```

Run the visible, animated integrated video gate separately so routine inventory
does not cover an artist's desktop unexpectedly:

```bash
./scripts/run-video-pipeline-qualification.sh
```

NvFBC 1.9 has no 10-bit output format. Streams from this backend must therefore
be labeled 8-bit-source/up-converted even though the local Xorg root is depth
30 and the encoder accepts a 10-bit 4:4:4 surface. A future native 10-bit mode
requires a new vendor-supported capture format; it must not be implemented by
patching Xorg.

The production media contract remains HEVC Range Extensions, 10-bit 4:4:4.
CUDA expands the 8-bit full-range BGRA components into the 10-bit 4:4:4 encoder
surface with `Y=G`, `U=B`, and `V=R`; it must not use NV12 or introduce chroma
subsampling. The encoder signals full range, matrix coefficient 0 (GBR), sRGB
transfer, and BT.709 primaries. Protocol and UI telemetry report source precision
and codec precision separately.

Sunshine must consume prepared FFmpeg artifacts from
`instinctual/build-deps`, branch `stationconnect/main`. Do not roll the entire
bundle back to the older API-13.0 release: its x265 archive references vector
math symbols unavailable on Rocky 9. The StationConnect fork pins the NV codec
headers and disables only GCC tree vectorization for x265; x265's hand-written
architecture-specific SIMD remains enabled.

The validated artifact is
`v2026.724.203728-stationconnect.4` (`4a54a631f8c217318c15c070141e3690a938d3e6`).
Its Linux x86_64 archive SHA-256 is
`c0ab243756a24506f536bf7a0a1c9bd7638bb6bcda14fa4ece820fa07e2bf5de`.
A clean configure downloaded that release by tag; Sunshine linked on Rocky 9,
initialized NvFBC, opened HEVC NVENC, and reported no API-version mismatch.

Linux uses a blocking NVENC output worker and two reusable input/output slots.
This decouples capture submission from an occasional slow encode while bounding
the waiting queue to one frame. Latency is measured from capture start until the
bitstream becomes available; the 25 ms local-pipeline target is not substituted
for the 16.67 ms 60 Hz budget.

On this Ada GPU, the final driver-auto split stress run produced a 15.959 ms
pipeline p95; disabling it increased p95 to 18.015 ms. Keep driver-auto on Ada,
never force it,
and retain an explicit unsplit test. NVIDIA split-frame encoding is unavailable
on the RTX A4500/A5000/A5500/A6000 Ampere and Quadro RTX 6000/8000 Turing hosts,
so every model must pass the same 2160p60 test without it.

The full looping workload independently confirmed the choice: driver-auto
reduced capture-to-bitstream p95 from 17.419 ms to 14.512 ms, with the 3.005 ms
improvement occurring in the blocking bitstream-lock wait. Both streams decoded
cleanly. Auto emitted 65.01 Mbps versus 52.99 Mbps for disabled at the same
80 Mbps configuration, so a frame-aligned rate-distortion test is still needed
before claiming equivalent compression efficiency.

The later fullscreen-footage pair is the preferred stress vector. Driver-auto
reduced capture-to-bitstream p95 from 17.321 to 14.290 ms and bitstream-lock p95
from 16.954 to 13.767 ms. The auto stream averaged 78.43 Mbps versus 53.20 Mbps
disabled. SFE therefore restores host frame-budget headroom on this Ada workload
but incurs a large compression-efficiency cost that must remain visible in
telemetry and network qualification.

A final committed-build recapture used a fullscreen 3,583-frame Flame sequence
looping at 24 fps. The first 9,000-frame driver-auto run observed 8,989 new
capture generations, sustained 60.00 fps, and averaged 78.56 Mbps. Pipeline
p95/p99 was 14.377/14.794 ms, leaving 2.290 ms of p95 headroom. One isolated
38.012 ms outlier caused one deadline miss, so the integrated gate passed but
the stricter zero-miss robustness gate did not. The bitstream SHA-256 is
`bae9b1a55ac6a058e1235d00d1bc231822bff14e1d954c7ff9762a9287244ebb`.

A clean repeat of that final workload is the production reference. Driver-auto
observed 8,980 new generations, encoded all 9,000 frames at 59.99 fps with no
drops or deadline misses, and passed the strict robustness gate. Capture,
conversion, and NVENC p95 were 0.167, 1.373, and 14.073 ms; end-to-end p95/p99
was 14.540/15.019 ms, leaving 2.127 ms of p95 headroom. Its average bitrate was
78.50 Mbps and SHA-256 is
`a483c4301590ae40b5621ee734db31a056860822a8874fd0223ce333bb07a0b1`.
The matched SFE-disabled run encoded all 9,000 frames at 60.00 fps with no
deadline misses, but its 17.587 ms p95 exceeded the frame budget by 0.920 ms
and failed the robustness gate. It averaged 53.13 Mbps; SHA-256 is
`dfb18707b03739540541beb3b369369ce4bceb8811658b259f9281dd6feff94f`.
Auto therefore improves p95 by 3.047 ms on the final sequence, at the previously
observed bitrate cost.

The probe accepts `--tuning low-latency|ultra-low-latency`. A controlled full-loop
A/B test found no material ULL benefit, matching the 4K HEVC observation in the
[2025 SFE evaluation](https://arxiv.org/html/2511.18687v1). Keep Low-Latency as
the production default unless a future GPU/driver-specific qualification shows a
repeatable improvement.

The full-loop intra-refresh matrix found no useful latency improvement from
counts 45 or 59, multi-slice refresh, or disabling refresh. The seven p95 values
spanned only 0.216 ms. Retain the one-second period, 30-frame single-slice wave:
it provides faster and simpler recovery without a meaningful latency penalty.

The animated test measures NvFBC capture-call latency. Its p95 value means 95%
of calls completed in that time or less; it does not include CUDA color
conversion, NVENC, transport, client decode, or presentation.

## Remaining Video Work

1. Repeat the fullscreen integrated gate on each Turing and Ampere host SKU.
2. Integrate the qualified Intel decode, identity, and presentation path into
   the client and measure network-to-photon latency with shared timestamps.
3. Expose the explicit
   `8-bit-source/up-converted` label.
4. Continue tuning toward the optional NVENC component p95 target of 8 ms.
5. Add transport FEC and compare post-recovery pixels with a synchronized
   no-loss reference before closing the packet-loss gate.

## End-of-Day Handoff

Qualified Ada host settings as of 2026-08-19 are P1/Low-Latency, driver-auto
SFE, HEVC Rext 10-bit 4:4:4, 80 Mbps CBR with a one-frame VBV, no AQ,
lookahead, multipass, or B-frames, and periodic intra refresh at period 60,
count 30, single-slice enabled. Capture remains NvFBC `BGRA8888` and must be
labeled 8-bit source/up-converted; CUDA uses the identity mapping
`Y=G,U=B,V=R`. The Linux output path is a blocking worker with two reusable
slots and at most one queued frame.

The Intel NUC Gen13 VA-API decode, identity shader, and 10-bit presentation
gates now pass. The preferred fullscreen artifacts are stored under the
repository's ignored qualification artifact directory:

```text
artifacts/qualification/video/stationconnect-flame-fullscreen-3583f24-final-sfe-auto-repeat2.hevc
sha256=a483c4301590ae40b5621ee734db31a056860822a8874fd0223ce333bb07a0b1
artifacts/qualification/video/stationconnect-flame-fullscreen-3583f24-final-sfe-disabled2.hevc
sha256=dfb18707b03739540541beb3b369369ce4bceb8811658b259f9281dd6feff94f
```

Do not spend more time on ULL or intra-refresh latency tuning: both full-loop
matrices showed only measurement-level differences. The next optional host
headroom experiments are a temporary NVENC/video-clock A/B and an explicitly
measured three-strip SFE test. Neither is approved as a persistent production
setting; both require bitrate and quality checks. Ampere and Turing unsplit
qualification, packet-loss recovery, PAM conversations, and Wacom
multi-interface UHID binding remain Phase 0 work.

### Generic modesetting DDX experiment

The isolated depth-30 modesetting DDX reached monitor discovery, selected
1280x2160 plus 3840x2160 modes, and initialized NVIDIA glamor. Startup then
failed while creating the screen pixmap because Xorg selected the `nouveau` DRI
provider for the proprietary `nvidia-drm` device. The active Autodesk/NVIDIA
Xorg configuration was not changed, and GDM was restored automatically.

A shadow-framebuffer control run did start at Xorg depth 30 and exposed a live,
exportable KMS framebuffer, but that framebuffer was `XR24` and rendering used
Mesa llvmpipe. It is therefore neither native 10-bit nor GPU accelerated and is
not a production option.

### Direct DRM experiment

With Xorg stopped, the standalone probe selected connector 131/CRTC 80 at
3840x2160/60, created and scanned out an `XB30` framebuffer, exported it as a
DMA-BUF, and imported it into NVIDIA EGL 1.5. This proves the kernel-side
10-bit/zero-copy primitives. This remains historical evidence for a possible
future backend and is not part of the production Xorg capture path.
