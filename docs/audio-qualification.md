# Audio Qualification

StationConnect currently streams coupled stereo Opus at 48 kHz using
`OPUS_APPLICATION_RESTRICTED_LOWDELAY`. The high-quality stereo target is
512 kbps total for both channels, not 512 kbps per channel. Existing Moonlight
audio Reed-Solomon recovery remains enabled independently of video FEC.

## End-to-End Delivery Gate

With a StationConnect session active, run the non-destructive loopback gate
from the repository root:

```bash
STATIONCONNECT_SSH_KNOWN_HOSTS=/path/to/known_hosts \
  ./scripts/run-audio-loopback-qualification.sh user@client
```

The runner resolves the client's default PipeWire sink, records that sink's
monitor, and injects a low-level 997 Hz tone into the host Sunshine sink. It
passes when the returned target band is at least 6 dB above a 3 kHz control
band. Pass a numeric PipeWire sink ID as the second argument when testing a
non-default output. WAV captures and metric files are written under
`artifacts/qualification/audio/` and excluded from Git.

Two live `hardware-test-host` to Intel NUC runs on 2026-08-21 passed with 11.70 dB and
13.60 dB target-to-control deltas. The second run used the restarted,
identity-bound session. They confirmed this path:

```text
host session sink -> Sunshine capture -> Opus/RTP -> Moonlight decode
                  -> PipeWire HDMI sink
```

The NUC opened a 720-sample stereo output buffer at 48 kHz, corresponding to
15 ms of audio per callback.

The restarted stream also passed the Stage A same-user ownership gate:
Sunshine, authenticated account `operator`, and the selected `remote-desktop`
logind session all resolved to UID `540600009`. This proves the permitted live
path; automated host tests cover rejection and cleanup for a UID mismatch.

## Clock-Drift Telemetry

Set `STATIONCONNECT_AV_SYNC_TELEMETRY=1` in the client's
`~/.config/stationconnect/client.env`, restart the client, and begin a new
stream. Moonlight then logs audio media time with its SDL queue/device latency
and video media time at the renderer call about once per second. Collect the
user-service journal and analyze it from the repository root:

```bash
./scripts/analyze-av-sync-telemetry.py moonlight.log \
  --warmup-seconds 180 --min-duration-seconds 7200 \
  --max-skipped-audio-blocks 0
```

The analyzer reports p95 clock jitter, corrected and raw audio clock rates,
the applied correction range, skipped audio blocks, accumulated relative A/V
drift, and a least-squares drift fit across the measurement window. Its one-hour
projection uses the fitted slope; a separately labeled endpoint projection is
retained to expose short-window noise. Optional
`--max-relative-drift-ms` and
`--max-projected-relative-drift-ms-per-hour` arguments turn those metrics into
explicit gates. The analyzer normalizes the streams' independent starting
epochs, so it does not claim absolute lip-sync offset. A synchronized
flash/tone source and client-side event detector remain necessary for that
measurement.

### Packaged baseline result

A changing-content scaled-span run with synchronized 0.3 packages failed the
relative-clock gate after 1,307.501 seconds. Raw relative drift reached
`-44.544 ms`; the least-squares fit projected `-95.947 ms/hour`. Audio and
video jitter p95 were 10 ms and 14 ms. The client reported no audio packet
loss, queue overflow, decrypt failure, or renderer reinitialization, and its
packet and SDL playback queues remained bounded.

The individual fits localized the mismatch to the audio delivery clock
(`-100.809 ms/hour`) rather than video (`-4.862 ms/hour`). This telemetry uses
decoded 5 ms audio-frame progress and renderer queue estimates; it proves the
two client media clocks are not held together, but it does not measure
absolute acoustic-to-photonic offset. The unchanged two-hour run was stopped
once it exceeded both 20 ms gates. Phase 7 now requires video-master audio
correction before repeating the soak.

### Adaptive-correction prototype

A 6 minute 35 second live scaled-span run on 2026-08-21 qualified the first
bounded video-master prototype. After a 180 second warmup, the 211.546 second
measurement window projected `-6.310 ms/hour` fitted relative drift and ended
at `5.751 ms` relative drift. The uncorrected audio clock still measured
`-290.035 ms/hour`, while adaptive resampling settled between 84 and 87 ppm.
No audio blocks were skipped and the SDL queue remained bounded. This passes
the 20 ms and 20 ms/hour development gates, but it is not the required two-hour
soak or synchronized flash/tone offset measurement.

## Remaining Phase 7 Gates

This tone test proves routing and decoded sample delivery; it does not prove
A/V synchronization. Before Phase 7 is complete:

- live-qualify the Stage A PAM-account/desktop-owner launch gate and reject
  cross-user audio access;
- measure audio offset against the video presentation clock, including p95 and
  p99 jitter;
- verify packet-loss recovery and bounded jitter-buffer behavior;
- run a two-hour changing-content test of bounded video-master correction with
  no audible glitches, skipped audio blocks, or accumulating A/V drift;
- measure a synchronized flash/tone source to establish absolute offset; and
- repeat disconnect and session-switch cleanup after the corrected soak.
