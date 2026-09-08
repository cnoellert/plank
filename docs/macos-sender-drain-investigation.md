# macOS sender-drain measurement

September 8, 2026. Diagnostic Host1.0.50-macos-host; exact source and binary
provenance in HANDOFF. User played two browser-video windows at5120x2160,
unchanged50Mbps encoder target/100Mbps peak. Capture/encoder settings match .48.
No pacing, FEC, queue-size or Client changes in this measurement.

## Observations

First120seconds began00:01:23 local time. Sender trace contains6618 completed
submissions,181 keyframes, and116 cumulative queue evictions at its final
dequeue. The full session ended00:03:59:8997 complete captures,1 pre-encode skip,
zero VideoToolbox drops,320 recovery-or-send drops,132 actual transport queue
evictions,8675 sent video frames,31292 audio packets and zero audio-send drops.
Recovery-or-send drops include deliberate dependent-frame suppression; do not
interpret320 as320 transport evictions or network packet losses.

| Average keyframe sender stage | Elapsed ms |
| --- | ---: |
| Copy, RaptorQ initialization and repair generation | 6.08 |
| Pacer reservation/wait, including scheduling delay | 60.29 |
| Quinn synchronous datagram submission calls | 14.01 |
| Remaining framing/control/dispatch work | 1.12 |
| Total after dequeue | 81.50 |

Average keyframe size928216bytes. Its average pre-dequeue residence was11.25ms
(separate from the above), and capture trace mean key encoding time22.16ms.
Sender-wide pacer elapsed accounts for70.78% of time inside submissions.

Frame4189 is a concrete causal sequence:

- Encoded1,601,896byte sample in25.819ms; packaged Annex-B frame1,601,981bytes.
- Dequeued with an empty pending queue and only0.018ms residence.
- RaptorQ/framing produced1628 datagrams totaling2,126,168bytes.
- Sender processing took139.354ms:8.574ms FEC preparation,101.769ms pacer,
  26.964ms Quinn calls, and the remaining small framing/control overhead.
- Next dequeued frame was4192, with86.8ms residence and3 other frames pending.
  Cumulative queue evictions rose74→76 while4189 drained:4190/4191 were lost
  locally before transmission. The recovery key4196 subsequently took130.105ms.

## Interpretation and limits

The encoder is not dropping output in this run. Large normal keyframes expose
the single-frame-at-a-time sender's drain-time mismatch with its four-frame
pending queue. At60fps four frames represent roughly67ms of arrivals; a125–139ms
drain readily exceeds that capacity. This supports a sender-side cause of the
observed stalls, not an inference that the Internet path itself is saturated.

Every traced frame used a136,000,000bps software budget, derived from the
configured100Mbps peak times1.35 plus1Mbps. This is not a measurement of available
link capacity. Frame4189's datagram bytes alone require125.069ms at that rate,
before FEC processing. Across keyframes the mean nominal serialization is72.51ms
versus81.50ms measured total; mean per-frame ratio1.122. Timer refinement alone
cannot eliminate that configured serialization budget.

Timers do warrant attention:34574 sleeps requested only1.342s in aggregate,
while total pacer elapsed was39.882s (roughly39us requested and1.15ms pacer
elapsed per sleep). But pacer elapsed includes reservations and scheduler delay;
the burst allowance and virtual timeline interact with wakeups. Do NOT call the
whole difference avoidable wasted time or assume a30x throughput improvement
from a more precise timer. Likewise Quinn call time includes locking and actual
submission, not exclusively contention. These are elapsed wall times, not CPU,
ACK or wire-delivery times. Instrumentation overhead was not independently
benchmarked; no synchronous per-frame log output occurred during playback.

## Next proposed experiment (not applied)

Keep encoder settings, Client, FEC policy and queue capacity unchanged. Test a
bounded sender burst budget that can drain a keyframe promptly while retaining
longer-term rate limits and network backpressure. Validate receiver loss and
latency rather than merely moving the backlog into Quinn or kernel buffers.
Do not remove pacing entirely, enlarge latency queues, switch congestion
controllers, or resume low-latency encoder changes on the strength of this trace.
Any shared transport policy change also needs Linux regression qualification.

Raw numeric log is retained outside Git at
`~/.cache/plank-build/work/host-sender-1.0.50.log`.
Reproduce with `scripts/analyze-sender-timing.py` and
`scripts/analyze-macos-frame-timing.py`. Align by frame number; capture sample
sizes omit Annex-B parameter-set additions included in sender payload sizes.
