# Upstream Integration Baseline

## Pinned Starting Points

Begin product work from released upstream revisions, while retaining the
standalone probes as hardware acceptance tests:

| Component | Release | Commit |
| --- | --- | --- |
| Sunshine | `v2026.817.185037` | `f0ea53694420d48303c6cfe95b12136c65ed5af5` |
| Moonlight-Qt | `v6.1.0` | `f786e94c7b2f943e24e65d7d74deb539b827fc84` |
| moonlight-common-c | Moonlight-pinned | `8599b6042a4ba27749b0f94134dd614b4328a9bc` |

Use project forks with `upstream` remotes; do not copy selected source files
out of context or squash away upstream history.

## Existing Upstream Foundation

Sunshine already provides the principal host pipeline:

- `src/platform/linux/cuda.cpp` implements NvFBC BGRA capture directly into
  CUDA memory.
- `src/video.cpp` negotiates HEVC Range Extensions 4:4:4 formats and supplies
  CUDA frames to Linux NVENC.
- `src/stream.cpp` packetizes frames into multiple Reed–Solomon FEC blocks and
  handles reference-invalidation and IDR control messages.
- `src/nvenc/nvenc_base.cpp` contains capability checks, reference invalidation,
  SFE selection, and intra-refresh configuration for the direct NVENC backend.

Moonlight already provides the client and recovery foundation:

- `app/streaming/session.cpp` negotiates `VIDEO_FORMAT_H265_REXT10_444`.
- `ffmpeg-renderers/vaapi.cpp`, `drm.cpp`, and `eglvid.cpp` implement VA-API,
  DRM PRIME, Y410, and EGL presentation paths.
- The pinned moonlight-common-c `RtpVideoQueue.c`, `VideoDepacketizer.c`, and
  `ControlStream.c` implement multi-block FEC, loss detection, reference-frame
  invalidation, and IDR escalation.

## StationConnect Delta

Extend these paths rather than replacing them:

1. Add an explicit Linux identity-GBR mode: NvFBC `BGRA8888` expands to 10-bit
   `Y=G,U=B,V=R`, with full range and matrix coefficient 0.
2. Report source, codec, and presentation precision separately; the baseline
   must say `8-bit-source/up-converted`.
3. Reuse Sunshine's control/FEC path, but qualify Linux NVENC reference
   invalidation, driver-auto SFE, and the tested 60/30 single-slice refresh wave.
   Sunshine's current direct-backend default of 300/299 is not the qualified
   StationConnect setting.
4. Extend Moonlight's VAAPI/DRM renderer for the proven Y410-as-XR30 identity
   interpretation. Avoid CPU mapping and retain the existing bounded decoder
   and presentation queues.
5. Add shared feature bits and diagnostics for identity mapping and precision;
   reject mismatched peers instead of guessing.
6. Keep PAM/no-pairing authentication and raw Wacom forwarding as narrow
   additions around Sunshine/Moonlight session and input infrastructure.

The qualification binaries remain independent on purpose: they are regression
oracles for upstream integration, not an alternate production transport,
encoder, decoder, or renderer.
