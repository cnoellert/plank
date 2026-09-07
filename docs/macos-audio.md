# macOS Host audio qualification

Experimental, macOS/SDK 27 only. The Host-first plan uses the existing Ubuntu
Client's Opus decoder and native audio transport. Do not introduce a temporary
Client audio codec, silent channel or preview-specific playback path.

## September 7 result

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

1. Qualify incremental AudioConverter input under realistic uneven capture
   callback sizes. Do not signal EOF during an ordinary temporary input gap.
   Bound buffering and characterize startup priming, steady-state packet output,
   reset and discontinuity behavior before embedding the encoder in capture.
2. Enable ScreenCaptureKit **system** audio for the authenticated desktop only,
   explicitly 48000 Hz/two channels; keep microphone capture off. Inspect actual
   CMSampleBuffer/AudioBufferList format rather than assuming interleaving.
3. Preserve source timestamps on the same monotonic basis as captured video;
   account for priming and partial packets once. Session/topology revocation
   must stop submissions and drain/drop old-user samples before a new owner.
4. Submit complete Opus packets through the existing native audio API with
   frame_samples=240 and matching timestamps. Qualify payload/timing preservation
   over QUIC, loss/discontinuity behavior and bounded receive queues.
5. Validate audible playback, synchronization and sustained A/V drift using the
   ordinary Client after the complete Host contract is ready. Offline codec
   compatibility is not end-to-end audio acceptance.
