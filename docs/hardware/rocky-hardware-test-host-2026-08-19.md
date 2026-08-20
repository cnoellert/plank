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
| NvFBC host-latency timestamp | Pass | All 600 display-render timestamps shared the host monotonic clock domain, with no zero, future, or nonmonotonic values. A live NUC session received Sunshine's host-processing telemetry. |
| Native 10-bit NvFBC source | Unsupported, non-blocking | NvFBC 1.9 exposes only 8-bit RGB/YUV output formats, including native `BGRA8888`; the approved baseline is labeled 8-bit-source/up-converted. |
| HEVC Rext 10-bit 4:4:4 encode | Pass | The integrated 600-frame stream decodes without error; `ffprobe` reports `Rext`, `gbrp10le`, full-range GBR identity signaling, sRGB transfer, and BT.709 primaries. |
| Live Sunshine/Moonlight identity session | Pass | The NUC negotiated format `0x800`, hardware-decoded to Y410, and imported the Y410/XR30 alias through EGL. After fixing startup queue priming, five fresh connections, one full loop, and a 10:20 soak all had exact pacer totals of `0/0/0`. Client diagnostics explicitly label the 8-bit source, 10-bit 4:4:4 codec, and 10-bit identity presentation stages. |
| NVIDIA driver/build-deps compatibility | Fixed in fork | Driver 580 exposes NVENC API 13.0. The StationConnect build-deps fork pins `nv-codec-headers` to API 13.0 and prevents GCC from introducing a glibc vector-math ABI into x265 that Rocky 9 does not provide. |
| Synthetic animated 2160p60 pipeline | Pass, marginal | The enforced rerun sustained 60.05 fps with zero submission misses and 15.959 ms p95, but its 16.862 ms p99 failed the stricter robustness gate. P95 headroom was only 0.708 ms. |
| Full looping production workload | Pass | The instrumented 150-second loop encoded 9,000 frames at 60.01 fps with 8,999 new captures, zero misses, 14.645 ms p95, 15.041 ms p99, and 2.022 ms p95 headroom. |
| Real-workload SFE A/B | Auto required on Ada | Matched 9,000-frame runs measured 14.512 ms p95 and 14.939 ms p99 with driver-auto, versus 17.419 ms p95 and 17.752 ms p99 with SFE disabled. Both decoded without error; only auto met the 16.67 ms budget. |
| Fullscreen-footage SFE A/B | Auto required on Ada | With footage filling the 3840x2160 capture output, auto measured 14.290 ms p95 and 2.377 ms headroom. Disabled measured 17.321 ms p95 and failed the budget by 0.654 ms. Both sustained 60.00 fps with no deadline misses. |
| NVENC Ultra-Low-Latency tuning | No material gain | A matched 150-second ULL run sustained 60.00 fps with zero misses and measured 14.644 ms p95 and 15.013 ms p99. The 1 us p95 difference from LL is noise, so LL remains the default. |
| NVENC 8 ms component target | Fail, non-blocking | NVENC completion p95 was 14.328 ms on the full loop. Its blocking bitstream-lock wait was 14.249 ms p95, while mapping, submission, and output-worker dispatch totaled under 0.1 ms at p95. The tail is inside NVIDIA's encode/completion path. |
| HEVC 10-bit 4:2:2 encode | Unsupported | Live capability query returns `caps_yuv422_encode=0`; NVIDIA added HEVC 4:2:2 encode after the Turing/Ampere/Ada fleet. |
| Intra-refresh latency matrix | Pass; retain 60/30 single-slice | Seven full-loop profiles covered refresh disabled and counts 30/45/59 with single- and multi-slice refresh. Pipeline p95 ranged only from 14.404 to 14.620 ms; disabling refresh gained just 0.108 ms over baseline. Every stream decoded all 9,000 frames. |
| Controlled-loss recovery continuity | Pass | Separate 600-frame real-content runs dropped access unit 180. Reference invalidation accepted timestamp 180 two frames later; the emergency path forced an IDR with VPS/SPS/PPS at frame 182. Both wrote exactly 599 pictures, retained the host robustness gate, and decoded all 599 pictures through Intel VA-API. Against a synchronized no-loss stream, Intel-decoded Y410 pixels matched before the loss, differed only at source frame 181, and regained permanent identity at frame 182. Live transport FEC separately recovered 5% random loss with 20% FEC and 10% random loss with 30% FEC. |
| Sustained extended-FEC recovery | Pass | A 180-second release run at 30% FEC and 10% random datagram loss dropped 127,982 datagrams. Moonlight recovered 9,130 blocks/97,906 shards; five unrecoverable frames healed through RFI with no decoder error or decoder-driven IDR. Decode/render sustained 59.94/59.87 fps. A validation build separately byte-checked 9,737 reconstructed blocks under the same profile. |
| DRM KMS API enablement | Pass | After reboot, `nvidia_drm.modeset=Y`; atomic modesetting and universal planes are exposed. |
| Active KMS scanout enumeration | Fail | All four DRM CRTCs and twelve planes report framebuffer ID 0 while NVIDIA Xorg drives two displays. |
| XR30/AR30 framebuffer and DMA-BUF export | Blocked | The NVIDIA Xorg session exposes no active scanout framebuffer through DRM KMS. |
| Direct native 10-bit KMS scanout | Pass | A standalone DRM master scanned out `XB30` at 3840x2160/60. |
| Native 10-bit DMA-BUF export/import | Pass | The `XB30` buffer exported successfully and imported into NVIDIA EGL 1.5 without CPU readback. |
| Direct NVENC required capabilities | Pass | API 13.0 exposes FRExt, 10-bit 4:4:4 input, intra refresh, reference invalidation, and single-slice intra refresh. |
| Linux direct NVENC integration | Pass, opt-in | The CUDA-backed `nvenc-direct` path produced live 2160p60 HEVC Rext 10-bit 4:4:4, retained identity GBR signaling, and completed FEC/RFI loss recovery with the Intel client. Automatic selection still prefers the established FFmpeg-backed `nvenc` path pending the remaining GPU matrix. |
| Physical Wacom discovery | Pass | USB `056a:0317` Intuos Pro L exposes pen, pad, touch, and two raw HID interfaces. |
| Generic UHID transport | Pass | A temporary generic mouse receives `UHID_START` and binds through the host kernel. |
| Wacom UHID binding | Pass | The exact grouped PTH-660 (`0357`) descriptors and physical feature-report replies produced `UHID_START` for both interfaces and native Pen, Pad, and Finger nodes on Rocky 9.7. |
| Normalized uinput tablet | Pass for core pen | Sunshine's existing libvirtualhid backend is recognized by Rocky libinput as `tablet`; its consumer test passes with event-node access. Pressure, distance, tilt, eraser, and three stylus buttons are represented. Pad controls, tool serials, barrel rotation, tangential pressure, and multitouch are not yet represented. |
| Live NUC-to-host raw Wacom | Pass | The NUC forwarded both physical PTH-660 HID interfaces bidirectionally. Flame received the real model geometry, pressure, tilt, pad, and touch capabilities; edge gestures and Flame-controlled Tablet Margins worked without a watcher or coordinate pre-scaling. |
| PAM/SSSD account policy | Pass | Root and `gdm` are rejected; authorized SSSD accounts `operator` and `testartist` pass account management. |
| PAM password/session conversation | Pending | Requires secure interactive tests for valid and invalid credentials. |

## Wacom UHID Qualification

Two physical generations were inventoried on the host. The PTH-851 exposes
234-byte pen/pad and 23-byte touch descriptors plus a boot-mouse interface.
The PTH-660 exposes 949-byte pen/pad and 549-byte touch descriptors, with a
shared serial number. Early incomplete replays accepted `UHID_CREATE2` without
reaching `UHID_START`, which was incorrectly classified as a Rocky kernel
limitation. Repeating the test with both exact descriptors grouped under one
physical identity and answering the physical feature reports succeeded on
Rocky 9.7 (kernel `5.14.0-611.55.1.el9_7`). Both interfaces reached
`UHID_START`; the stock driver requested feature reports `0x0c` and `0x23` and
sent feature report `0x32`.

The resulting nodes match the physical PTH-660: pen range `44800x29600`, 8191
pressure levels, distance 63, two-axis tilt, wheel/rotation, pad ring, and
finger range `8960x5920`. No Xorg or kernel change is required. USB/IP remains
only a fallback if a future model cannot bind through exact raw HID/UHID.

## Wacom Transport Direction

The production device is physically connected to the Ubuntu NUC, not the
workstation. The client owns and reads the tablet while a stream is active,
sends ordered tablet events to the workstation, and releases the device back
to the Ubuntu desktop at disconnect. The workstation creates the virtual
tablet consumed by XInput2, libinput, and Flame. Host-connected tablets in this
report are qualification fixtures only.

Sunshine's existing normalized pen transport and libvirtualhid uinput backend
remain a clearly labeled core-pen fallback. The upstream
`LinuxConsumerTest.LibinputSeesUinputPenTabletTool` passed on this workstation
when run with permission to read the generated event node. A non-root run
could create the device through world-writable `/dev/uinput` but could not read
the root:`input` event node; production packaging must grant only the required
helper access rather than broad input-device access.

The first physical end-to-end run on 2026-08-20 used a PTH-660 attached to the
NUC. The client udev rule granted the active session access to only the pen
node (`event15`); pad and touch remained inaccessible. Moonlight grabbed that
node while focused and Sunshine exposed `libvirtualhid Pen Tablet` as a Rocky
libinput tablet. A 10.3-second active sample produced 1,845 events with
proximity in/out, absolute motion, distance, pressure tip up/down, and tilt.
The run also uncovered a shifted aggregate initializer that left Sunshine's
`native_pen_touch` default false. The initializer and a default-value
regression test now keep native pen negotiation enabled.

The subsequent raw-HID bridge granted the active NUC session access to both
`hidraw` interfaces and all three event nodes, grabbed pen/pad/touch as one
device group, and relayed input and control reports in both directions. Rocky
exposed the real `Wacom Intuos Pro M` stylus, eraser, pad, and finger devices.
XInput captured native pressure, distance, tilt, tip transitions, and absolute
motion from the raw stylus source. The user confirmed full-screen reach, the
Ctrl plus bottom-edge Flame gesture, and Flame's 5% and 20% Tablet Margins.
Only the normal `3840x2160+0+0` output mapping was applied; Flame controlled
its own margins.

The same attach/input/GET_REPORT/SET_REPORT/output state machine now runs in
the authenticated, encrypted Sunshine/Moonlight control channel. The
integrated session reproduced the client's two descriptors, USB identity, and
event capability bitmaps; disconnect removed all host nodes and reconnect
created them again. The user reconfirmed the Ctrl plus bottom-edge Flame
gesture and Flame-controlled Tablet Margins on this production path. The
standalone TCP bridge remains qualification-only. Automated ExpressKey, ring,
multitouch, hot-unplug, and abrupt network-loss coverage remains before the
full Wacom product gate can close.

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

The fork now exposes the same SDK 13 direct encoder machinery on Linux through
an opt-in CUDA adapter named `nvenc-direct`. It supports NV12, P010, planar
4:4:4, and planar 10-bit 4:4:4 input, but it is deliberately listed after the
FFmpeg-backed `nvenc` encoder. Do not make it the automatic default until the
Turing and Ampere qualification matrix passes.

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

## Software Encoder Qualification

A current isolated toolchain was built under the ignored `build/third-party/`
tree: FFmpeg 9.0.1, x264 `0480cb05fa18`, and x265 4.2
`e444744c0397`. Tests used the fullscreen 3,583-frame Flame sequence at
3840x2160x60, the `ultrafast` preset, no B-frames or lookahead, GOP 60, and a
100 Mbps CBR/2 Mbit VBV. Ten-bit results remain 8-bit NvFBC source
up-converted. X11grab is not usable because FFmpeg 9.0.1 does not implement the
active depth-30 X11 root format.

| Software path | Result |
|---|---|
| x264rgb native 8-bit RGB 4:4:4 | 9,000 moving frames supplied at 60.00 fps; 150.195 s encoder wall time; 100.017 Mbps. |
| x264 8-bit 4:4:4, CUDA GBR identity | 9,000 moving frames supplied at 60.00 fps; 150.252 s encoder wall time; 100.015 Mbps. |
| x264 10-bit 4:4:4, CUDA GBR8 identity plus CPU depth expansion | 9,000 moving frames supplied at 60.00 fps; 150.241 s encoder wall time; 100.011 Mbps. |
| x264 10-bit 4:4:4, CUDA GBR10 identity and direct planar readback | Failed at 45.75 fps because the 16-bit planar carrier is 49.77 MB/frame. |
| x265 8-bit 4:4:4 | Failed at 37.32 fps. |
| x265 10-bit 4:2:2 | Failed at 33.78 fps. |
| x265 10-bit 4:4:4 | Failed at 31.16 fps. |

The x264 identity streams were independently parsed as High 4:4:4 Predictive
`gbrp`/`gbrp10le`, full range, GBR matrix, with the requested 8/10-bit depth.
The native `libx264rgb` stream was likewise parsed as High 4:4:4 Predictive
8-bit `gbrp`, full range, GBR matrix. This encoder accepts only 8-bit
`bgr0`/`bgr24`/`rgb24`; it has no native 10-bit RGB input mode.
CUDA identity conversion reduced the 8-bit host transfer from 33.18 to 24.88
MB/frame and cut FFmpeg user CPU time by about 27% in the controlled 10-second
comparison. Across the long run, native x264rgb used 540.2 user CPU-seconds
versus 471.8 for CUDA identity, about 14% more, while wall-clock throughput was
equivalent. Native RGB is simpler, but CUDA identity transfers less data and
uses less CPU. Two, four, and eight x265 frame threads did not reach 60 fps;
the best observed result was 56.89 fps and added multiple frames of latency.

Direct blocking `x264_encoder_encode()` instrumentation corrected the earlier
throughput-only conclusion:

| Direct path | Completion latency and capacity |
|---|---|
| x264rgb native 8-bit RGB | 140.36 fps on a preloaded moving sample; 8.60 ms p95, 9.33 ms p99, 11.59 ms maximum; 0/600 calls over 16.67 ms. |
| x264 8-bit GBR identity | 178.16 fps; 6.86 ms p95, 7.44 ms p99, 10.92 ms maximum; 0/600 calls over budget. |
| x264 10-bit GBR identity | 107.44 fps including startup; after a 60-frame warmup, 10.57 ms p95, 11.40 ms p99, 14.21 ms maximum; 0/540 steady-state calls over budget. The first call was a repeatable allocation outlier, so production must warm the encoder before publishing the stream. |
| NVENC H.264 8-bit GBR identity, blocking | 104.66 fps in an unpaced pipeline sample. The accepted 9,000-frame loop measured 17.47 ms completion p95 and 17.82 ms p99. A separate 600-frame run put 96/600 completions and 116/600 capture-to-bitstream intervals over budget. |
| NVENC H.264, bounded one-frame async | Did not reduce availability latency: paced completion p95 was 17.47 ms and capture-to-bitstream p95 was 17.87 ms. |

The H.264 NVENC result is a tail-latency failure despite low reported encoder
utilization: average capacity exceeds 60 fps, but blocking completion is
bimodal near 7 and 17 ms. Native x264rgb is the strongest 8-bit RGB result on
this workstation, but it cannot produce the required 10-bit stream. The
10-bit x264 identity path is now the leading CPU candidate after warmup.

### Integrated x264 identity comparison

The Sunshine/Moonlight implementation was exercised on 2026-08-20 for 190
seconds per mode against the fullscreen Flame loop. Sunshine used NvFBC,
`software-cuda`, `ultrafast`/`zerolatency`, 33 x264 threads, and a 100 Mbps
client request. The process and all existing worker threads had to be expanded
from the desktop session's inherited eight-CPU affinity to CPUs 0-127; results
without that correction are invalid for capacity qualification.

| Integrated path | Client result |
|---|---|
| x264 10-bit GBR identity, eight-worker exact depth expansion | 59.97 fps received/decoded and 59.96 rendered; 36.2 ms host-processing p95; 6.29 ms decode; 0.00% network loss, 0.03% jitter loss, pacer `0/3/0`. |
| x264rgb native 8-bit RGB | 59.97 fps received/decoded and 59.96 rendered; 31.9 ms host-processing p95; 4.93 ms decode; 0.00% network loss, 0.02% jitter loss, pacer `0/2/0`. |

The eight-worker exact 8-to-10-bit expansion improved the earlier integrated
10-bit result from 59.66/59.61 fps received/rendered and 42.2 ms
host-processing p95. DP-2's active physical timing is 59.973 Hz (533.250 MHz,
4000-by-2223 totals), so 59.97 fps received and decoded is full source-monitor
cadence and closes the encoder-throughput portion of the 60 fps gate. The NUC
output is 60.000 Hz. Rendering was 59.96 fps because both modes recorded client
catch-up drops, so the strict zero-drop portion remains open. Host processing
starts at the NvFBC display-render timestamp and ends at packetization; it is
not x264 encode-completion latency. The direct per-call completion and
maximum-capacity figures remain the values in the table above. Raw client logs
are retained under the ignored
`artifacts/qualification/video/software-x264-2026-08-20/` directory.

### Final instrumented software baseline

The final run separated display age, CUDA readback/conversion, x264 completion,
packet readiness, client decode, pacing, and renderer-call time. The 10-bit run
covered 10,710 encoded frames of the fullscreen Flame loop at 78.99 Mbps; the
8-bit native-RGB control covered 4,384 frames. Both used 33 x264 threads,
`ultrafast`, `zerolatency`, four slices, and the physical 59.973 Hz DP-2 source.

| Host boundary (p95) | x264 10-bit identity GBR | x264rgb native 8-bit |
|---|---:|---:|
| Display timestamp to conversion start | 19.47 ms | 16.17 ms |
| CUDA conversion/readback | 14.48 ms | 12.76 ms |
| GPU readback synchronization alone | 11.38 ms | 12.74 ms |
| CPU 8-to-10-bit expansion | 3.88 ms | not applicable |
| x264 completion | 11.24 ms | 12.07 ms |
| Display timestamp to packet ready | 36.13 ms | 32.72 ms |
| Packet-ready interval | 23.74 ms | 24.20 ms |

The mean packet-ready intervals were 16.678 ms and 16.666 ms respectively,
which explains how throughput reaches the physical refresh rate while the
per-frame latency p95 exceeds one refresh. Only 2 of 10,710 10-bit x264 calls
exceeded 16.67 ms. The principal latency tails are capture scheduling and GPU
readback; 10-bit expansion adds a smaller, bounded cost.

On the NUC, the 10-bit client measured decode p95/p99/max of 11/12/29 ms,
pacer-queue 13/19/48 ms, and renderer-call 8/9/87 ms. It received 59.97 fps
with zero network loss but recorded 11 render catch-up drops (0.10% jitter).
The native 8-bit control measured 8/9/15 ms decode, 12/14/38 ms queue, and
4/5/80 ms renderer-call latency, with one render catch-up drop. These calls do
not provide hardware presentation timestamps; network-to-photon remains a
separate presentation task. Raw logs are in the ignored
`artifacts/qualification/video/software-x264-2026-08-20/final-instrumented/`
directory.

Sunshine's StationConnect software backend now selects `libx264rgb` for native
8-bit RGB or `libx264` with identity GBR planes for the 10-bit path. The latter
is explicitly labeled `8-bit-source/up-converted`. NVENC HEVC remains a
qualified comparison—the moving-content full-loop run had zero deadline
misses, 14.645 ms p95, and 15.041 ms p99—but is on hold while the product is
built around the software paths.

The timestamp-qualified NvFBC probe measured display-render-to-capture-return
age at 8.033 ms average, 15.432 ms p95, and 16.676 ms maximum over 600 frames.
Sunshine now preserves that timestamp through CUDA conversion and NVENC for new
frames, allowing the existing protocol field to report display-render start to
packetization. A 60-second live NUC run reported 4.2/34.1/17.1 ms
min/max/average host processing, sustained 59.99 fps at every client stage,
lost no packets, and recorded exact pacer totals of `0/0/0`. This metric starts
earlier than the qualification probe's capture-to-bitstream timer, so those
values must not be compared as equivalent measures. Moonlight commit
`4628bd82` added an exact fixed-memory histogram; a complete 170-second client
run measured host-processing p95 at 29.2 ms, sustained 60.00 fps at every
stage, and retained zero network, jitter, and pacer drops. This p95 includes
display-render phase plus the overlapping encode pipeline, so exceeding one
refresh interval does not imply a 60 Hz throughput miss.

## Deferred Video Follow-up

1. Repeat the fullscreen integrated gate on each Turing and Ampere host SKU.
2. Integrate the qualified Intel decode, identity, and presentation path into
   the client and measure network-to-photon latency with shared timestamps.
3. Revisit codec tuning only if a release gate fails; NVENC remains on hold and
   the x264 paths are the current software baseline.

Reference-invalidation pixel healing and live transport FEC now pass. Debug
validation proved 9,992 clean-link and 9,737 loss-injected reconstructed
real-content shards byte-identical to their originals. The sustained-loss run
also found and corrected stale extended-block metadata in recovered packets;
the release repeat used RFI for all five residual frame losses without an
emergency IDR.

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
qualification, packet-loss recovery, PAM conversations, and full Wacom
feature coverage remain Phase 0 work.

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
