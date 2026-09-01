# hardware-test-host native X11 10-bit capture feasibility

Date: 2026-08-26

Branch: `native-x11-10bit`

The branch now contains an opt-in prototype host backend. NvFBC remains the
packaged default and is unchanged.

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
frames. Ordinary `XGetImage()` consumes the complete 60 Hz frame interval and
is not a production candidate.

A separate 120-frame, 60 Hz paced test against moving Flame footage produced
124 distinct sampled fingerprints. Direct-window XShm capture measured 5.845
ms median and 7.693 ms p95. Mutter unredirects fullscreen Flame from the
XComposite overlay, making an overlay capture black unless compositing is kept
active. A transparent 2x2 override-redirect, input-empty keepalive window
restored live overlay capture; that path measured 7.310 ms median and 8.313 ms
p95. Enabling NVIDIA Force Composition Pipeline did not restore the overlay by
itself and increased the observed median to about 31 ms, so it is neither a
requirement nor a substitute for the compositor keepalive.

The existing Sunshine X11 backend copies its SHM staging frame into a second
image buffer. On this canvas that copy measured 8.457 ms median. It must not be
retained in a low-latency implementation. A direct eight-way CPU conversion
from packed RGB 10:10:10 into planar 10-bit identity GBR measured 3.032 ms
median and 3.195 ms p95, including per-frame thread creation. Persistent
workers should improve that result. The implemented persistent eight-way
conversion measured 1.892 ms median and 2.338 ms p95 in the integrated stream.

## Integrated stream result

An unattended 82-second Development NUC session exercised the opt-in backend
at 3840x2160, 60 Hz, H.264 High 10 4:4:4 identity, PC range. The host verified
the depth-30 XComposite source and exact masks; the client accepted only the
matching software `gbrp10le` decoder path. Measured results were:

- 60.13 incoming/decode FPS and 59.79 rendered FPS
- zero incoming packet loss and zero network frame drops
- 5.66 ms average client decode time
- 15.6 ms average host processing latency, 17.2 ms p95
- 1.892 ms median packed-RGB10-to-planar-GBR10 conversion
- 8.762 ms median x264 completion time
- clean disconnect and exact pre-session physical MetaMode restoration

The current client performance overlay still labels an H.264 High 10 identity
stream as `8-bit-source/up-converted` because source precision is not yet a
negotiated protocol field. Host capture and encoder logs are authoritative for
this prototype. Correcting that client label requires a synchronized protocol
change and is not hidden by this host-only candidate.

## Candidate design constraints

- Preserve NvFBC as the default and unchanged qualified backend.
- Add an explicit opt-in capture value, `x11-native10`; do not initially add
  automatic fallback between source depths.
- Require an authenticated X11 session, MIT-SHM, an XComposite overlay matching
  the selected canvas, depth 30, 32-bpp storage, and exact 10:10:10 RGB masks.
- Fail clearly if any native-precision gate is absent.
- Allocate a ring of owner-restricted SHM-backed capture images so Xorg writes
  directly into the image owned by the capture/encode pipeline. The privileged
  worker transfers each segment to the authenticated X server account rather
  than making it globally writable.
- For unscaled identity GBR software encoding, split packed 10-bit RGB directly
  into the encoder's planar 10-bit system-memory frame. A CUDA upload/readback
  would add two transfers while both endpoints are already in system memory.
- Keep CUDA available for scaling or non-identity conversion only after a
  measured prototype proves it is faster than the CPU path.
- Log the selected capture backend and verified source pixel layout for every
  stream.
- Limit the prototype to 1:1 source and encode dimensions. Scaling is rejected
  clearly until a measured native-precision scaling path is implemented.

## Reproduction

The probe is built from the repository root:

```bash
cmake -S . -B build/qualification -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/qualification --target plank-probe-x11-native10 --parallel
```

Run it as the active X11 session owner with the session's `DISPLAY` and
`XAUTHORITY`:

```bash
plank-probe-x11-native10 --shm-frames 600 --get-frames 3
```

No captured pixels are written to disk or printed. The probe reports only
format metadata, timing summaries, controlled round-trip status, sampled code
counts, and processing benchmarks.
