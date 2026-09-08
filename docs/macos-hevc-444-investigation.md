# VideoToolbox HEVC 10-bit 4:4:4 investigation

September 8, 2026. Qualification and candidate integration on the dedicated Apple M4 development
Mac: macOS 27.0 build 26A5425a, SDK 27.0, arm64, deployment target 27.0.
The initial investigation did not change the installed Host. Candidate1.0.64
is now installed on the dedicated development Mac; see the integration record.

## Result

**Accepted September 8:** the operator tested candidate1.0.64 and reported
"That works. I accept", authorizing commit, push and merge. This is functional
acceptance of the additional profile, not a claim that every remaining
instrumented release gate below was exercised. No queue/transport change or
format fallback was added after the tested candidate.

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

## Live ScreenCaptureKit qualification

After operator desktop login, the guarded owned-chart tests ran on the same
M4/SDK27 combination. The installed Host was not replaced or restarted.
The signed Probe was temporarily replaced, then restored with its original
SHA256 `6056054b6c99fe0195220bc9b991d21a7850d5378e037cd2df32b8dc8bd02f77`.
Every run verified capture/encoder teardown and removal of its owned display;
the temporary graphical job and probe processes are absent afterward.

Both 3840x2160 and 5120x2160 captured exact IOSurface-backed `xf44` and encoded
with hardware Main44410. Actual SCK samples are untagged, full-range BT.601
YCbCr: interpreting the chart as 709 gives 32.662 maximum error in 8-bit
equivalent units, versus 2.000 for 601 (including the coarse grayscale ramp).
Declaring this measured source matrix lets VideoToolbox convert to full-range
BT.709 output without an application pixel-buffer conversion/copy. Decoded
sample agreement is 0.138 maximum in 8-bit equivalent units. This is NOT RGB
identity, and these coarse chart samples do not qualify native 10-bit desktop
precision or one-pixel chroma retention across ScreenCaptureKit.

Independent private FFmpeg 9.0.1 inspection on linux-client-builder confirms each saved
chart keyframe as HEVC Rext, `yuv444p10le`, PC/full range, BT.709 primaries and
matrix, sRGB transfer, and exact 4K/5120x2160 dimensions. Independently decoded
4K primary patches differ from ideal full-range BT.709 by at most 0.793 of one
10-bit code unit; black/white are 0/1023. Only the guarded chart keyframe is
saved, not arbitrary desktop video. Temporary linux-client-builder inspection copies
were removed after retaining artifacts in the root's ignored `build/`.

| Live chart run | Submitted/encoded | Overflow | FPS | Mean/p95/max encode callback ms |
| --- | ---: | ---: | ---: | --- |
| 4K | 897/897 | 0 | 60.000 | 15.928/16.227/40.122 |
| 5K initial | 897/897 | 1 | 59.933 | 20.658/21.011/50.219 |
| 5K repeat | 897/897 | 1 | 59.933 | 20.580/20.863/48.433 |
| 5K diagnostic 1 | 898/898 | 0 | 60.000 | 20.519/21.061/47.843 |
| 5K diagnostic 2 | 896/896 | 2 | 59.866 | 20.973/21.538/64.466 |
| 5K diagnostic 3 | 892/892 | 1 | 59.933 | 20.596/21.048/49.188 |
| 5K diagnostic 4 | 897/897 | 1 | 59.933 | 20.682/20.966/48.465 |

Runs last approximately 15 seconds. Encoder drops are zero throughout. Added
bounded probe-only overflow reporting locates all observed diagnostic skips
at submitted frame 3 or 4, 0.184–0.217 seconds after initialization; none occur
later. This supports startup pressure, not sustained encoder backlog, but the
strict zero-overflow gate **remains open**. Do not hide those failures, increase
queues silently, or extrapolate this simple moving-marker chart to complex
5K60 footage. Capture-to-submit timing is unavailable for these xf44 callbacks;
encode callback timing is not glass-to-glass latency.

The unchanged older 4K Main10/x420 speed-chart control also passed color,
858/858 encode, zero overflow/drop and cleanup. It retains its historical
1/60 SCK interval and measures 57.324 FPS; it is not a same-cadence performance
comparison or a test of the installed full-range Host profile.

Diagnostic-2 executable SHA256:
`f56dfcb1f57b30fe4a86849f1bb3dc9055e07e9b299e456c906018adf1794d4e`.
It adds logging only; SDK27 warnings-as-errors build and signing pass.
Retained chart hashes:

- `build/hevc444-live-4k.hevc`: `7d0a24e8927755e104800184f851bca72a2084fe12deb94149c73e4b0bfa56df`
- `build/hevc444-live-5k.hevc`: `a5039d0808fa094b85a4a6d14b746b83e87686d9ffc20dfe60e1ed092b4f1c8a`

## Candidate integration

The `macos-hevc444` branch now implements a separate per-bookmark Apple HEVC
10-bit 4:4:4 profile. Authenticated display schema 2 includes the exact encoding
mode; topology generation includes that mode, and launch rejects disagreement.
SCK/VideoToolbox select xf44/Main44410 for this profile and retain xf20/Main10
for 420, including encoder replacement on bitrate changes. Hardware encoding
is required; no silent fallback or Linux RGB-identity substitution is allowed.
Client hardware-first decoder probing uses the owned-chart 444 keyframe and
checks RExt/10-bit/444/full/709/sRGB; runtime frames retain the same checks.

Focused Client tests on linux-client-builder pass: 58 Apple frame-contract checks with
real software-decoded 420/444 fixtures, 123 launch checks, 15 topology tests,
and nine bitrate-policy tests. Synthetic hardware metadata is not hardware
decode qualification. Full Mac Host compilation and native-media lifecycle
tests pass; updated control/capture-generation tests pass. Full candidate
packaging now passes too. The signed Host1.0.64-macos-hevc444 is installed on
the dedicated Mac; the Client DEB is retained for manual graphical acceptance.
Actual service discovery/unauthorized denial/graceful replacement pass. A
stale test-only bitrate adapter was updated to the existing asynchronous
interface, and old test/installer branch-name checks now accept the actual
version while preserving signature and exact runtime-version checks.

Live4K444 format-only receive passes51frames, two independently decoded
keyframes,2992Opus packets, four10/150Mbps command ACKs and clean disconnect.
The unchanged4K420 full decode test passes52network/49decoded frames and
2992Opus packets with the same ACK/disconnect checks. These are static desktop
runs, not moving-content performance or visual acceptance.

The first synchronous4K444 software-decode harness run on GPU-less linux-client-builder
fell behind at frame8→11, with two receive-queue drops and missing-reference
decode failure; Host recorded zero send drops. The format-only runner now
drains promptly and decodes bounded retained keyframes after disconnect,
without changing product code. A first5K format-only run received49frames
but failed the test's two-keyframe minimum because the static desktop had
only one. The explicit format-only gate now accepts one; this does not qualify
bitrate-driven re-encoding under motion or excuse reference-chain failures.
Final5120x2160 run passes52network frames, two exact decoded444 keyframes,
2992Opus packets, all four bitrate ACKs and clean disconnect. Hardware Client
rendering, smooth moving footage, login/logout and final OS revalidation remain.

A startup experiment with `MaxFrameDelayCount=1` was rejected by VideoToolbox
with OSStatus -12900 before frame submission. It is not in production or the
retained probe source. The original installed Probe was restored and verified.
No queue size, transport, FEC, or application pacing changes accompany this
feature. The observed one/two pre-encode source skips at some 5K starts remain
an explicit qualification limit, not encoded reference-frame loss.

## Remaining qualification

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
formats. The signed SDK27 build and live color checks pass; 5K startup overflow
and end-to-end moving-content qualification remain open.
Use the existing Mac runbook's backup/install/run/restore procedure at the
consented Probe path. The ordinary installed Host must remain untouched during
this component gate. No active Client stream may be disrupted for the probe.

Diagnostic source is in ignored `build/vt444-probe.m`, reusing the existing
`probes/macos/annexb-sample.h`. Encoded samples and first-frame raw inspection
are retained under ignored `build/`. No release or package was built.
