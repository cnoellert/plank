# Intel NUC Client Qualification

Run this gate on every supported NUC generation with its production Ubuntu
kernel, `intel-media-va-driver` (`iHD`), libva, FFmpeg, GStreamer's `vah265dec`,
compositor, and display. On Ubuntu, install `gstreamer1.0-plugins-bad` for the
VA decoder. The DMA-BUF probe additionally needs `build-essential`, `pkgconf`,
`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`, and `libdrm-dev`.
The Wayland presentation probe needs `wayland-protocols` and the Wayland/EGL
development libraries. It uses the staging commit-timing protocol when the
compositor advertises it.
Copy both the Ada driver-auto and SFE-disabled HEVC test streams from
`artifacts/qualification/video/` to the NUC.

```bash
./scripts/probe-intel-vaapi-decode.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-auto-paired.hevc \
  9000

./scripts/probe-intel-vaapi-decode.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-disabled.hevc \
  9000

./scripts/probe-intel-vaapi-dmabuf.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-disabled.hevc \
  9000

./scripts/validate-intel-identity-pixel.sh \
  artifacts/qualification/video/stationconnect-flame-loop-150s-sfe-disabled.hevc \
  600

XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
  ./scripts/probe-intel-wayland-xr30.sh 9000

XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
  ./scripts/probe-intel-client-pipeline.sh \
  artifacts/qualification/video/stationconnect-flame-fullscreen-loop-150s-sfe-auto.hevc \
  9000
```

The script fails unless VA-API exposes `VAProfileHEVCMain444_10` with the VLD
entry point, the stream retains the full-range GBR identity metadata, GStreamer
negotiates a Y410 VA-memory surface, all requested frames decode, and average
throughput reaches 60 fps. It counts hardware buffers at a VA-only pipeline
boundary; requesting FFmpeg `-hwaccel vaapi` alone is not proof because FFmpeg
may silently fall back to software. For the current long-loop vectors:

```text
auto_sha256=21c2007a97c7fc777b98dd24e5aba9fc1b62f2f2b3453f8bc9d72f1d62118fe1
disabled_sha256=261157e974092e704b6ec4b799a1dabddfd3efbfc86ca6286b6e7a0282dfcad1
fullscreen_auto_sha256=7a60394a6d3ee2bd1de948ef673bb2204d9d8c465d25ae1b9def663fa3593156
fullscreen_disabled_sha256=cf0ce9cb7035c62e49d872f3a6b718f9cd441f3860753525364d9a93d0aba185
frames=9000
resolution=3840x2160
codec=HEVC Rext 10-bit 4:4:4
```

Decode throughput is only the first gate. Use the DMA-BUF probe to qualify an
EGL import without an 8-bit copy. The client implementation must then reverse
the `Y=G,U=B,V=R` identity mapping in its shader, verify channel order with pixel
patterns, and measure decode-to-presentation p95 against the 8 ms target.

## NUC13ANKi7 Result — 2026-08-19

The NUC has Raptor Lake-P Iris Xe graphics (`8086:a7a0`), Ubuntu 26.04, Mesa
26.0.8, libva 1.23, and Intel iHD 26.1.2. The driver advertises HEVC Main444
10-bit VLD with `VA_RT_FORMAT_YUV444_10`. Its active 3840x2160/60 Wayland scanout
is XR30, independently proving a 10-bit RGB display path.

The Intel hardware path accepts the unchanged stream. GStreamer 1.28.2
negotiates `main-444-10` directly to `video/x-raw(memory:VAMemory),format=Y410`
on `/dev/dri/renderD128`. Both complete real-content artifacts pass:

| Stream | Frames | Elapsed | Average throughput |
| --- | ---: | ---: | ---: |
| Ada driver-auto SFE | 9,000 | 40.013 s | 224.93 fps |
| SFE disabled | 9,000 | 37.991 s | 236.90 fps |

These are accelerated-throughput results, not per-frame latency percentiles.
They average 4.45 and 4.22 ms per frame respectively, leaving ample throughput
capacity for 60 Hz.

FFmpeg 8.0.1 identifies the correctly signaled stream as `gbrp10le` and silently
falls back to software even when VA hardware frames are requested. Earlier
FFmpeg measurements of 95.78 and 109.52 fps are therefore invalidated. Do not
change the stream's GBR matrix metadata to work around an FFmpeg negotiation
issue. The client should use the proven Y410 VA surface and import it without a
CPU copy.

The dedicated DMA-BUF probe requests the required `GstVideoMeta` allocation,
checks every output memory and FD without mapping it, and imports a representative
frame through EGL with the advertised modifier. Both 9,000-frame vectors passed:

| Stream | DMA-BUF throughput | Surface |
| --- | ---: | --- |
| Ada driver-auto SFE | 225.29 fps | Y410, modifier `0x0100000000000002` |
| SFE disabled | 237.50 fps | Y410, modifier `0x0100000000000002` |

The preferred fullscreen-footage stress pair also passed. Driver-auto decoded
at 248.83 fps and disabled at 251.09 fps. The auto stream's higher 78.43 Mbps
rate therefore does not threaten the NUC's decode throughput.

The surface is one 3840x2160 plane with a 15,360-byte stride. Mesa does not
expose `GL_EXT_YUV_target` on this GPU, so the client uses the RGB-identity
method instead of a YUV sampler. Y410 packs `A:V:Y:U`; importing the same
DMA-BUF storage as XR30 interprets those fields as `X:R:G:B`. Sampling it as an
external RGB EGL image therefore reconstructs `R=V,G=Y,B=U` without a matrix,
copy, or loss of precision.

Frame 600 of the real SFE-disabled loop passed an independent center-pixel
comparison. Software decoding produced `R=183,G=177,B=168`; the VA-API Y410
DMA-BUF, XR30 alias, and GLES shader produced the same three 10-bit values. The
decoded surface was never CPU-mapped; readback was limited to the two-pixel
test output.

The fullscreen Wayland probe selected AR30 (`10:10:10:2`) at 3840x2160 and
completed a 9,000-frame, 150-second soak. Swap submission p50/p95 was
0.023/0.034 ms. Wayland frame-callback p50/p95 was 16.662/16.755 ms, which
represents 60 Hz compositor cadence rather than GPU processing time.

The integrated probe timestamps each access unit immediately before
`vah265dec`, decoded DMA-BUF availability, EGL swap submission, and the
`wp_presentation` hardware event. It waits for presentation before submitting
the next frame, keeping the maximum queue depth at one. Both fullscreen vectors
presented all 9,000 frames with hardware-clock, hardware-completion, and vsync
feedback:

| Stream | DMA-BUF fps | Surface-to-swap p95 | Submit-to-present p95 | Zero-copy frames |
| --- | ---: | ---: | ---: | ---: |
| Driver-auto SFE | 248.83 | 0.192 ms | 17.038 ms | 8,995 / 9,000 |
| SFE disabled | 251.09 | not recorded | 17.028 ms | 8,997 / 9,000 |

The auto run's decoder-submit-to-surface p95 was 0.201 ms and swap-call p95 was
0.135 ms. Surface availability is not proof that Intel's asynchronous decode
engine has completed; the hardware presentation timestamp is the authoritative
end boundary. The actual p95 is one 60 Hz refresh because this strictly serial
probe begins the next decode only after the prior frame is presented. The newer
cadence gate shows that this mode can miss refreshes even though every requested
frame is eventually presented. It also fails if the 8 ms client target is
defined as submit-to-photon.

A controlled 300-frame phase test scheduled decoder input 6 ms before a
hardware-derived target vblank. The controlled results were:

| Mode | Lead | Effective fps | Submit-to-present p95 |
| --- | ---: | ---: | ---: |
| Serial | 6 ms | 29.85 | 22.614 ms |
| Threaded | 0 ms | 60.00 | 50.318 ms |
| Threaded | 1 ms | 59.60 | 34.178 ms |
| Threaded | 6 ms | 60.00 | 39.257 ms |

The 1 ms case missed refreshes and is not a valid 60 Hz result. All 300 frames
in the 6 ms threaded control were hardware-clocked, vsynced, and zero-copy.
However, a 60-frame repeat at the same setting missed two refresh intervals,
averaged 58.03 fps, and reached 55.945 ms p95. The threaded result is therefore
not repeatably qualified even at the higher-latency setting.
Mutter accepted a `wp_commit_timing_v1` timestamp on every scheduled frame, but
it did not eliminate the extra vblank; that protocol constrains presentation
to occur no earlier than the requested time and does not guarantee same-vblank
latching. Threading is therefore a throughput mechanism, not the latency fix.
Keep the production queue bounded and investigate asynchronous feedback or a
direct-display path before adopting it. Network-to-photon remains unmeasured
because this file-backed probe starts at decoder submission rather than packet
arrival.
