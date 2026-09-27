# Source-timestamp A/V baseline

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

Only replace the current estimated correction if the minimal clock-publication
fix and baseline identify a remaining error. The zero-returning inherited pending-audio query
and inactive backlog controller must not be treated as transport-queue telemetry.
