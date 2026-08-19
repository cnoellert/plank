# Intel NUC Client Qualification

Run this gate on every supported NUC generation with its production Ubuntu
kernel, `intel-media-va-driver` (`iHD`), libva, FFmpeg, GStreamer's `vah265dec`,
compositor, and display. On Ubuntu, install `gstreamer1.0-plugins-bad` for the
VA decoder. The DMA-BUF probe additionally needs `build-essential`, `pkgconf`,
`libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`, and `libdrm-dev`.
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
capacity for 60 Hz, but decode-to-presentation p95 remains unmeasured.

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

The surface is one 3840x2160 plane with a 15,360-byte stride. The next gate is
raw packed-channel sampling, the identity `B,G,R` swizzle, pixel comparison, and
XR30 presentation. EGL-image creation alone does not prove channel order or
10-bit presentation.
