# VideoToolbox HEVC 10-bit 4:4:4 investigation

September 8, 2026. Investigation only, on the dedicated Apple M4 development
Mac: macOS 27.0 build 26A5425a, SDK 27.0, arm64, deployment target 27.0.
No installed Host, Client, capture, display, input or service changes.

## Result

`kVTProfileLevel_HEVC_Main44410_AutoLevel` is exported in the SDK's
VideoToolbox.tbd but absent from VTCompressionProperties.h. Runtime `dlsym`
resolves it to the CFString `HEVC_Main44410_AutoLevel`. The hardware session's
supported ProfileLevel list advertises that value.

A standalone synthetic probe requires hardware acceleration, supplies an
IOSurface-backed `xf44` (full-range biplanar 10-bit 4:4:4) source and explicitly
selects that profile. RealTime, no frame reordering, speed priority, 60 Hz
expected rate, 120-frame keyframe interval and 40 Mbps average target are set.
All property writes and encoder preparation succeed. Runtime reports hardware
true and encoder `com.apple.videotoolbox.videoencoder.ave.hevc`.

| Dimensions | Frames encoded / independently decoded | Mean callback ms | Maximum ms |
| --- | ---: | ---: | ---: |
| 1280x720 | 30 / 30 | 3.943 | 19.288 |
| 3840x2160 | 30 / 30 | 11.426 | 28.444 |
| 5120x2160 | 30 / 30 | 14.796 | 32.096 |
| 5120x2880 | 30 / 30 | 19.382 | 42.582 |

The retained private FFmpeg 9.0.1 on linux-client-builder independently decodes all
frames and identifies HEVC Rext, `yuv444p10le`, PC/full range, BT.709 matrix and
primaries, sRGB transfer, and the exact dimensions for all four outputs.
The Main10 control at 720p reports `yuv420p10le`, hardware true and 3.886 ms
mean. A separate 4K Main10 encode control averages 10.864 ms (27.141 ms max).

These are 30 serial submissions of one static synthetic image, including
startup. They are NOT sustained moving-content throughput, 5K60 qualification,
capture latency, glass-to-glass latency or an apples-to-apples quality benchmark.
The 5K2880 serial result exceeds a 60 Hz frame period and merits particular
attention in a later bounded asynchronous throughput test.

First decoded 4K frame contains 869 distinct luma values, not an 8-bit-only
ramp. A 100x40 interior sample of one-pixel alternating chroma measures mean
absolute errors of 0.670 Cb and 0.575 Cr in 10-bit code units, maximum 2 and 1.
This supports preservation of fine chroma detail rather than merely relabeling
4:2:0 output. It is not lossless compression or RGB identity qualification.
The synthetic luma ramp covers codes 64 through 940, so it does not separately
validate preservation of the full-range black/white endpoints.

## Chromium reference

[Chromium revision 1b22d8ec](https://chromium.googlesource.com/chromium/src/media/+/1b22d8ec07e0ac9f07daa3e689e481d45f9220a1)
adds Apple Silicon hardware-only HEVC Rext support behind a disabled-by-default
high-bit-depth feature. Its implementation selects
`CFSTR("HEVC_Main44410_AutoLevel")` for P410 input, probes hardware per
profile/input-format combination, and does not advertise a software Rext
fallback. It supplies exact source-format/range attributes and maps full-range
P410 to the same `xf44` format used in this probe. IOSurface input handling is
relevant to retaining a shared-surface capture-to-encoder path. It does not
establish RGB identity or an Apple public API stability guarantee.

An earlier [Apple developer forum report](https://developer.apple.com/forums/thread/837412)
describes these exported-but-undocumented values working; it had no Apple reply
when inspected. Local runtime and bitstream tests are the stronger evidence for
this particular hardware/OS combination. No Chromium code was copied.

## Proposed next work, not implemented

Qualify SCK `xf44` capture into the hardware Main44410 encoder without an
application CPU readback/copy. The current installed Host requests `xf20`
4:2:0 and Main10; changing only the profile cannot restore discarded chroma.
SDK 27's SCK header explicitly lists `xf44` as supported. Verify actual source
pixels, range/matrix, both desktop and LoginWindow, then exact Ubuntu Client
hardware decode/presentation and moving 4K/5120x2160 workloads. Retain the
accepted 4:2:0 profile as a distinct choice; no silent format substitution.
Keep runtime hardware/profile probing and final-OS revalidation because the
profile constant is undocumented. RGB identity is a separate investigation;
the successful tests here are full-range BT.709 YCbCr 4:4:4.

## Qualification branch and ordered integration

Work continues on `macos-hevc444`, from main `54ef054`:

1. Pass owned-chart SCK xf44 capture/hardware Main44410 color checks at 4K and
   5120x2160. Inspect encoded chroma/depth/range independently. Compare source
   601 versus 709 interpretation; do not relabel samples without measurement.
2. Add an explicit Apple HEVC 10-bit 4:4:4 bookmark profile alongside accepted
   Main10 4:2:0. Synchronize capability/launch metadata, exact format validation,
   bitrate/profile selection and statistics. Never reuse Linux RGB-identity
   fixtures for YCbCr decoder qualification. No transport/FEC/pacing changes.
3. Qualify the existing Client exact hardware decoder and presentation with a
   genuine Apple 444 sample; preserve hardware-first/exact-software fallback
   and reject mismatched chroma, depth, range or matrix. Add protocol vectors
   and negative tests before matched candidate builds.
4. Test desktop and LoginWindow capture, transition/reconnect, bitrate changes,
   and moving-content 4K/5120x2160 timing through the ordinary Client. Keep
   5120x2880 as a separate probe result, not an unqualified new bookmark mode.
5. Build/install only after affected gates pass, preserve 420 regression tests,
   and ask for operator visual acceptance. No merge implied by this work.

The signed multi-mode probe now accepts `--pattern-hevc444-4k` and
`--pattern-hevc444-5k`. Both require an existing unlocked desktop; create and
retire a separate owned display/chart through the existing bounded lifecycle.
New synthetic sample-position checks pass for all four supported 420/444 pixel
formats. The signed SDK27 build passes; real capture tests await desktop login.
Use the existing Mac runbook's backup/install/run/restore procedure at the
consented Probe path. The ordinary installed Host must remain untouched during
this component gate. No active Client stream may be disrupted for the probe.

Diagnostic source is in ignored `build/vt444-probe.m`, reusing the existing
`probes/macos/annexb-sample.h`. Encoded samples and first-frame raw inspection
are retained under ignored `build/`. No release or package was built.
