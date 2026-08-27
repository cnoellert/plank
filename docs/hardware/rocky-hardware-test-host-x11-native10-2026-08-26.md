# hardware-test-host native X11 10-bit capture feasibility

Date: 2026-08-26

Branch: `native-x11-10bit`

This probe is an experiment only. It does not change the qualified NvFBC
capture path or any installed StationConnect package.

## Result

Native 10-bit X11 capture is feasible on the qualified hardware-test-host Xorg stack when
the capture drawable is the XComposite overlay and the transfer uses
`XShmGetImage()`.

The authenticated GNOME/Xorg session reported:

- root and XComposite overlay depth: 30
- storage: 32 bits per pixel
- channel layout: three non-overlapping 10-bit masks
- canvas: 5120x2160
- frame storage: 44,236,800 bytes
- MIT-SHM: available

A visible grayscale pattern containing every code from 0 through 1023 was
captured exactly through both XShm and the XComposite overlay. A real Flame
frame contained 874 to 896 distinct sampled codes per channel. This proves the
path is not limited to an 8-bit X11 image representation. The observed desktop
distribution alone is not treated as proof of application source precision;
the controlled visible 1024-code round trip is the precision gate.

## Timing

For 600 consecutive full-canvas captures of a static real Flame frame:

| Operation | Median | p95 | Maximum |
| --- | ---: | ---: | ---: |
| XShmGetImage | 5.306 ms | 5.453 ms | 15.388 ms |
| XGetImage | 17.318 ms | 17.318 ms | 18.063 ms |

The occasional 14-16 ms XShm samples appear to coincide with fresh compositor
frames. A paced moving-footage test remains required before qualification.
Ordinary `XGetImage()` consumes the complete 60 Hz frame interval and is not a
production candidate.

The existing Sunshine X11 backend copies its SHM staging frame into a second
image buffer. On this canvas that copy measured 8.457 ms median. It must not be
retained in a low-latency implementation. A direct eight-way CPU conversion
from packed RGB 10:10:10 into planar 10-bit identity GBR measured 3.032 ms
median and 3.195 ms p95, including per-frame thread creation. Persistent
workers should improve that result.

## Candidate design constraints

- Preserve NvFBC as the default and unchanged qualified backend.
- Add an explicit opt-in capture value, `x11-native10`; do not initially add
  automatic fallback between source depths.
- Require an authenticated X11 session, MIT-SHM, an XComposite overlay matching
  the selected canvas, depth 30, 32-bpp storage, and exact 10:10:10 RGB masks.
- Fail clearly if any native-precision gate is absent.
- Allocate a ring of SHM-backed capture images so Xorg writes directly into the
  image owned by the capture/encode pipeline.
- For unscaled identity GBR software encoding, split packed 10-bit RGB directly
  into the encoder's planar 10-bit system-memory frame. A CUDA upload/readback
  would add two transfers while both endpoints are already in system memory.
- Keep CUDA available for scaling or non-identity conversion only after a
  measured prototype proves it is faster than the CPU path.
- Log the selected capture backend and verified source pixel layout for every
  stream.

## Reproduction

The probe is built from the repository root:

```bash
cmake -S . -B build/qualification -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/qualification --target connect-probe-x11-native10 --parallel
```

Run it as the active X11 session owner with the session's `DISPLAY` and
`XAUTHORITY`:

```bash
connect-probe-x11-native10 --shm-frames 600 --get-frames 3
```

No captured pixels are written to disk or printed. The probe reports only
format metadata, timing summaries, controlled round-trip status, sampled code
counts, and processing benchmarks.
