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

The live `hardware-test-host` to Intel NUC run on 2026-08-21 passed with an 11.70 dB target
to control delta. It confirmed this path:

```text
host session sink -> Sunshine capture -> Opus/RTP -> Moonlight decode
                  -> PipeWire HDMI sink
```

The NUC opened a 720-sample stereo output buffer at 48 kHz, corresponding to
15 ms of audio per callback.

## Clock-Drift Telemetry

Set `STATIONCONNECT_AV_SYNC_TELEMETRY=1` in the client's
`~/.config/stationconnect/client.env`, restart the client, and begin a new
stream. Moonlight then logs audio media time with its SDL queue/device latency
and video media time at the renderer call about once per second. Collect the
user-service journal and analyze it from the repository root:

```bash
./scripts/analyze-av-sync-telemetry.py moonlight.log \
  --warmup-seconds 10 --min-duration-seconds 7200
```

The analyzer reports p95 clock jitter, accumulated relative A/V drift, and a
one-hour projection. It normalizes the streams' independent starting epochs,
so it does not claim absolute lip-sync offset. A synchronized flash/tone source
and client-side event detector remain necessary for that measurement.

## Remaining Phase 7 Gates

This tone test proves routing and decoded sample delivery; it does not prove
A/V synchronization. Before Phase 7 is complete:

- live-qualify the Stage A PAM-account/desktop-owner launch gate and reject
  cross-user audio access;
- measure audio offset against the video presentation clock, including p95 and
  p99 jitter;
- verify packet-loss recovery and bounded jitter-buffer behavior; and
- run a two-hour changing-content test with no audible glitches or accumulating
  A/V drift, followed by disconnect and session-switch cleanup checks.
