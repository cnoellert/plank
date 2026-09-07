# macOS Host audio qualification

Experimental, macOS/SDK 27 only. The Host-first plan uses the existing Ubuntu
Client's Opus decoder and native audio transport. Do not introduce a temporary
Client audio codec, silent channel or preview-specific playback path.

## September 7 synthetic codec result

On the dedicated development Mac (macOS 27 beta 26A5425a, SDK 27), Apple's
AudioToolbox reports an Opus encoder (`aenc/opus/appl`). AudioConverter creation
accepts 48000 Hz stereo with 120, 240, 480 and 960 frames per packet. This
inventory alone is not evidence of actual packet production.

The actual synthetic encode test uses interleaved Float32 stereo at 48000 Hz,
240 frames/5 ms per output packet, and a requested 96000-bit/s bitrate. It feeds
two seconds of a 440-Hz left/880-Hz right signal at peak amplitude 0.25. Apple
produced 402 packets, 27696 compressed bytes. Its reported priming is 312 frames
(6.5 ms), trailing frames zero. This is **not** measured capture-to-speaker
latency, nor proof of the Linux encoder's restricted-low-delay mode. The bitrate
request is not a measured CBR guarantee.

On linux-client-builder, the installed libopus 1.6.1 decoder used the ordinary Client's
stereo multistream layout: one stream, one coupled stream, channel map `[0,1]`.
Every packet reports and decodes exactly 240 frames. Total decoded output is
96480 frames; startup/EOF padding must be accounted for, not hidden. A central
one-second window has RMS 0.177832/0.176745, with wanted/unwanted tone separation
68.1/67.8 dB. All output samples are finite and below full scale.

No Client source/build/deployment change was required for this test. No
microphone, system-audio capture, speaker playback, permission change or
network media session was started. The fixture contains generated tones only.
No additional Mac codec dependency was installed.

## Incremental input, reset and live capture

The synthetic encoder now tests uneven chunks (1–1000 frames), repeated empty
input callbacks and a reset after a partially encoded silence stream. Temporary
starvation returns a callback error with zero frames, as documented by
AudioConverter.h; only actual EOF returns success with zero frames. Process
output even when the converter returns the temporary-starvation status.
Whole-input, incremental and reset fixtures are byte-identical (SHA-256
`60ae4e3781d00279c71d89fc6f047f5b7937fbfd80080a469e77ff704db29535`).
Both streaming cases exercised 810 starvation callbacks without EOF padding
or prior-stream samples leaking into the new fixture. This is codec reset
qualification, not a desktop-user transition test.

Signed standalone Probe 46 then captured live ScreenCaptureKit system audio:

- 48 kHz stereo, **planar Float32**, 960 frames/20 ms per callback.
- 428 chunks/410880 frames; maximum timestamp continuity error 0 microseconds.
- Every chunk encoded into four 240-frame/5-ms Opus packets: 1712 packets total.
- Encoding time per 20-ms chunk: p95 0.720 ms, maximum 0.785 ms.
- Audio callback age relative to the host clock, excluding the first 50 chunks:
  min 40.650 ms, median 53.904 ms, p95 65.696 ms, max 68.451 ms.
- A quiet generated stereo tone was detected; maximum RMS 0.017754.

Age refers to the **first sample** in the chunk, not its last sample, decoder
delay or speaker latency. The short test used metadata-only 64x64/10-fps video
alongside audio; it is not representative 4K A/V performance or a sync soak.
SCK does not deliver audio every 5 ms here, even though the encoder does produce
5-ms packets. Do not hide capture age by substituting callback-arrival time for
source PTS. Apple reports an additional 312-frame/6.5-ms codec priming value;
exact decoded-sample alignment still needs its own timing gate.

The bounded eight-second live test runs in the developer's existing Aqua
session, uses existing recording consent, and explicitly disables microphone
capture. It plays a two-second quiet tone through the OS-selected default
output, without changing routing. System samples and compressed output are
discarded after aggregate measurements; no recorded audio, screen image or
network audio is persisted. Capture/playback stop and the temporary Aqua job
is removed. This standalone invocation does not qualify authenticated-product
capture isolation or automatic owner changes.

## Native packet submission

`host/macos/media/native-audio.{h,m}` submits complete encoder-produced stereo
Opus packets through the existing native API. It creates no worker, resampler,
retry queue or alternate transport. The caller supplies the packet's source
presentation time after accounting for encoder priming. Audio wire PTS uses
**milliseconds**, matching the current Linux sender; video uses **90-kHz ticks**,
matching the existing Client assembler. The native transport preserves these
values without converting units. The Client currently passes audio packets to
Opus without consuming their PTS; preserving source time is not by itself proof
of synchronized playback.

The adapter requires an activated lease, ready endpoint and valid topology.
Enqueue is ordered with revocation using the same narrow boundary as video.
Malformed input, duplicate/backward timestamps and non-contiguous packet times
are rejected. A source discontinuity requires explicit owner reset/teardown,
not silent padding. Native DROPPED means the current packet was accepted while
an older queued packet was evicted; no extra retry buffer is added.

The standalone real-QUIC loopback passed **3239 checks**: all 402 generated
Apple packets were received byte-identically with 240-frame duration and exact
millisecond PTS, including a fractional source-clock origin. Pending lease,
invalid PTS, duplicate/gap, topology denial and latched desktop revocation were
checked; no packet arrived after the completed revocation test. Authentication
is synthetic in the test only. The adapter is now wired into the capture owner
as described below. Public discovery and the ordinary Client remain gated.

## Authenticated Host integration

`media/opus-encoder.m` is the reusable AudioToolbox implementation. It validates
ready PCM sample buffers, exact rate/channels/precision, finite samples, buffer
bounds and source timing. It accepts at most 8192 frames per callback, borrows
the retained CoreMedia audio buffers through the final starvation callback,
and bounds output draining to 40 calls. CoreMedia may copy to meet its requested
16-byte alignment; this is not a zero-copy audio claim. The encoder adds no
PCM queue, worker, resampler or fabricated silence channel.

Output PTS starts at source PTS minus the encoder-reported priming duration,
then advances exactly 240/48000 seconds per packet. Input timing is derived
from the original source time and total samples, not rounded chunk increments.
Allow only hardware-clock representation error at the two endpoints, calculated
using `mach_timebase_info` plus nanosecond CMTime rounding. The constructor
rejects a clock whose tolerance would reach half an audio sample. A missing or
overlapping sample, source-format change or sink failure stops the encoder and
latches failure. Do not silently synthesize timestamps to hide real gaps.

The production-encoder test passes **3646 checks**. Interleaved, planar and
uneven-chunk encodes are byte-identical; 96000 source frames produce 400 packets
before stop, with no EOF flush. Source gaps/overlaps, format changes, non-finite
input, oversized chunks and sink failure all latch stop. The uneven-chunk case
also reproduces a 41-nanosecond source timestamp offset, without changing output
timestamps or accepting the separately tested full-sample gap. A fresh encoder
is required for a new session. Ubuntu's unchanged Opus decoder accepts all 400
packets. A 100-ms synthetic-waveform comparison estimates **311 frames** of
delay, within one sample of Apple's reported **312**; this supports the priming
correction but is not capture-to-speaker synchronization acceptance.

`preview-session.m` creates both native media adapters only after QUIC is ready
and the lease is activated. `screen-capture.m` supplies audio and video from the
same SCStream, using the same serial owner queue and source-clock basis. Audio
is 48-kHz stereo, microphone is explicitly off, and the Host's own process audio
is excluded. Disconnect/revocation stops native submission first, stops and
disposes the audio encoder without flushing, then drains SCK/video callbacks
before freeing the borrowed endpoint. Both adapters survive abandoned-owner
cleanup until the asynchronous drain completes. The extended lifecycle suite
passes **222 checks/9 scenarios**, including audio revoked before stop.

The loopback qualification launch now reports `services.audio=true`; its strict
receiver verifies actual 240-frame packets and five-millisecond PTS increments
alongside video. The paused Client launch draft still expects video-only and is
intentionally not updated: it is not a working product path. Do not lift its gate
or call its historical manifest-test results acceptance of the current Host.

Early live integration passed a three-second A/V connection, then showed an
intermittent longer-run stop. Probe 48's narrow failure diagnostics identified
an actual source timestamp offset of **41 nanoseconds**, consistent with the
dedicated Mac's hardware clock granularity. The earlier one-nanosecond tolerance
was incorrect. Probe 49 uses the clock-derived tolerance above, not a larger
audio queue or relaxed whole-sample continuity. See HANDOFF for final run results.
The first uninstrumented stop had insufficient diagnostics to prove the cause;
the subsequent reproduced failure and its regression test establish the clock
issue without asserting that every possible stop is solved.

## Reproduce

Build `probes/macos/audio-codecs.c` (inventory) and
`probes/macos/audio-encode.c` (actual synthetic encode) **only on the dedicated
development Mac**:

```bash
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
  -mmacosx-version-min=27.0 probes/macos/audio-codecs.c \
  -framework AudioToolbox -o "$probe_build/audio-codecs"
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror \
  -mmacosx-version-min=27.0 probes/macos/audio-encode.c \
  -framework AudioToolbox -o "$probe_build/audio-encode"
"$probe_build/audio-codecs"
"$probe_build/audio-encode" "$probe_build/synthetic-opus.pao"
"$probe_build/audio-encode" "$probe_build/incremental.pao" --incremental
"$probe_build/audio-encode" "$probe_build/reset.pao" --reset
cmp "$probe_build/synthetic-opus.pao" "$probe_build/incremental.pao"
cmp "$probe_build/synthetic-opus.pao" "$probe_build/reset.pao"
```

Use a fresh output directory. The encoder refuses to replace an existing
fixture. `PAO1` is a standalone test-file container, **not a new wire protocol**:
four magic bytes, little-endian rate/channel/packet-frame u32 values, then a
u32 byte count plus each complete Opus packet. There is no recorded audio.

Transfer the fixture and SHA-256-check it on linux-client-builder, then:

```bash
cc -std=gnu11 -Wall -Wextra -Werror tests/audio/macos-opus-compatibility.c \
  $(pkg-config --cflags --libs opus) -lm -o "$test_build/opus-compatibility"
"$test_build/opus-compatibility" "$test_build/synthetic-opus.pao"
```

This links the existing system Opus library, not a replacement Client decoder.
It performs no audio-device initialization or playback. Repeat against the final
macOS 27 release before accepting the Apple encoder as a product dependency.

## Next Host gates

1. Extend authenticated combined audio/video qualification: retained source
   clocks, real source gaps, reset and session/topology
   revocation: stop submissions and drop old-user samples before a new owner.
2. Qualify integrated live audio over QUIC, loss/discontinuity behavior and
   bounded receive queues. The fixture loopback is not an induced-loss test.
3. Validate audible playback, synchronization and sustained A/V drift using the
   ordinary Client after the complete Host contract is ready. Offline codec
   compatibility is not end-to-end audio acceptance.
