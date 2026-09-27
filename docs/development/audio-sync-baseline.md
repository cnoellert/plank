# Source-timestamp A/V baseline

## Current follow-up: 1.1.029-audio-playback-safety

Candidate029 guards the existing phase correction using SDL output demand,
instead of a producer-side fixed queue cutoff. It does not add a playback
buffer, change the zero-phase target or delay video. Positive catch-up stops
when an output pull leaves less than one source block, then resumes after
three consecutive pulls retain two blocks. Infeasible phase targets must not
be chased by exhausting audio; this is a safety constraint, not sync acceptance.
When reserve is low, a headroom-derived negative correction ceiling allows the
same smooth resampler to recover it, even with a faster device clock. Merely
stopping catch-up failed that extended test in028. This can retain a few more
milliseconds of audio, so absolute A/V offset is an explicit acceptance gate.

`PLANK audio output demand` records cumulative pulls, shortage requests and
missing input bytes, the last request duration and residual input headroom,
observation age and catch-up-blocked state. These are SDL demand measurements,
not physical output timestamps or acoustic-underrun counts. Conversion can
conservatively overestimate requested input. The callback has no logging,
allocation or added buffer; logging remains on the decoding worker.

Repeat the real listening/flash-click soak against027 using the same Host,
output device, content and transport. Record crackles and sync direction with
wall time. Require no growing drift AND acceptable absolute lip-sync; do not
accept stable-but-offset audio or simulations alone. Correlate demand counter
deltas with source timing, correction and separately observed transport loss.
No live029 soak has yet been performed.

## Previous follow-up: 1.1.027-audio-sync

The1.1.026 long-session baseline established remaining drift. Candidate1.1.027
replaces the relative sample-count correction for common-clock macOS Hosts with
bounded source-phase correction. The same timing line now feeds control as well
as diagnostics; `observation_only=0` identifies that policy. Positive correction
ppm speeds consumption up and negative ppm slows it. Linux Host epochs remain
independent and retain the existing relative-rate policy, not absolute sync.

Compare1.1.027 against the saved1.1.026 baseline over at least one hour, ideally
three. Record audio direction, initial offset and whether it grows; retain all
timing, source-gap and queue values. Include idle-to-moving video and a normal
reconnect without changing the output device or Host version mid-comparison.
This build is not accepted on simulated results alone. The measurement caveats
below still apply. Over two hours of real027 playback, estimated phase remains
bounded, unlike026, but the operator reports brief crackles and occasional
video holds. One reported crackle coincides with no audio concealment requests
and brief empty SDL input observations. That supports playback investigation,
not proof of a hardware underrun or absence of all source/delivery glitches.

## Previous baseline: 1.1.026

Candidate 1.1.026-audio-sync restores video-clock publication for EGL renderers
that consume the AVFrame. Pacer snapshots PTS before rendering instead of reading
the reset source frame afterward. The existing correction controller can now
receive its video reference on this path. Output routing, buffering, correction
limits and video presentation are unchanged; no extra delay is introduced. The
common-C audio callback now carries source microseconds instead of discarding
the native transport's millisecond timestamp. No wire format changes.

The earlier 1.1.025 diagnostic candidate did not yet fix this ownership bug;
its EGL video reference remains invalid. Use 1.1.026 for live testing.

The Client product log records one `PLANK A/V source timing` line per second,
without an environment switch or recording the screen/audio. For a macOS capture
source, `common=1 valid=1` permits interpreting `estimated_lead_us`: positive
means audio is ahead of video, negative means audio is behind. It subtracts the
current SDL input queue, estimated device buffer, and swresample-held duration
from the next decoded audio packet's source timestamp, comparing that with the
last rendered video timestamp projected to the observation time.

This is **estimated enqueue-to-output alignment**, not measured acoustic or
photonic timing. SDL's queue is unconsumed input, its device buffer is not the
complete PipeWire/hardware latency, and the video clock is render-call completion,
not the display's scanout time. A stable offset requires a flash/click measurement
before diagnosing capture latency. See SDL's
[queue semantics](https://wiki.libsdl.org/SDL3/SDL_GetAudioStreamQueued).

`valid=0` suppresses interpretation when the video clock is stale/future, timing
is invalid, or source clocks have independent epochs. Linux currently reports
`common=0`; its audio sample counter cannot be directly compared with video PTS.
`gaps` counts source discontinuities greater than the wire's millisecond
quantization, including backward changes. Loss-concealment frames extrapolate
the last known source timestamp; a hole before the first packet is unknown.
Reconnecting resets the extrapolation. Input validation bounds malformed PLC
requests to prevent unbounded synchronous decoding.

Procedure: confirm exact versions, play a synchronized flash/click source,
observe whether the offset is already present or develops, and collect at least
one hour of Client logs with corresponding Host capture timing/overrun logs.
Compare offset changes with queue occupancy, timestamp gaps and applied rate
correction. No artificial loss or session interruption without operator approval.
The existing sample-count analyzer does not parse these new source-clock lines;
do not present its normalized drift as an absolute source-clock measurement.

Use `python3 scripts/test/analyze-source-audio-timing.py CLIENT_LOG` for the new
lines. It selects the latest nonempty renderer/session segment, excludes invalid
or independent-clock samples, and reports signed estimated offset, drift slope,
queue depth, clock discontinuities and correction range. A short fitted slope is
not an hour-long soak; duration and measurement limitations are printed explicitly.

The follow-up removes the inactive backlog controller and its SDL drop checks.
The zero-returning inherited pending-audio query must not be treated as real
transport-queue telemetry in older logs.
