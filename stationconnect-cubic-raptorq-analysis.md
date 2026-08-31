# StationConnect Kyber/RaptorQ Congestion Problem — Analysis and Recommendations

This is an unusually well-framed writeup, and the diagnosis is correct. Below: quantitative confirmation of the diagnosis, an argument that the "FEC-aware rate controller" isn't a risky invention but the standard, well-precedented design for this problem class, and answers to the 15 questions.

## The measured numbers match loss-based CC theory exactly

CUBIC (and its Reno-friendly mode) has a steady-state throughput ceiling determined by loss rate and RTT, roughly `rate ≈ (MSS/RTT)·√(1.5/p)`. At p = 0.005 with 1344-byte packets, that's ~17 packets of average window — a few Mbps at 40 ms RTT, tens of Mbps at the few-millisecond RTTs likely between the 203.0.113.x peers. QUIC's per-epoch (rather than per-packet) reduction pushes the achievable rate up somewhat, and the measured 16–63 Mbps band is precisely where loss-limited CUBIC lands for that loss rate on a short-RTT path. Nothing is malfunctioning. CUBIC is doing exactly what its model says, and the model is simply wrong for this traffic: it assumes loss = congestion and that the application wants max throughput with elastic tolerance. This traffic is inelastic, carries application-layer erasure coding, and experiences (partly) non-congestive loss. No buffer, beta tweak, or MTU change fixes a model mismatch.

The second, distinct failure is the amplification: 370 network losses became ~250,000 locally evicted datagrams — a ~675× amplification, and worse, *correlated* eviction (whole runs of symbols from the same frames), which is the one loss pattern RaptorQ per-frame coding cannot survive. The 30% redundancy was never actually tested by the network; it was defeated at the sender. These two failures need two fixes, and both belong in the design regardless of which controller is chosen.

## Precedent: this is GCC/SCReAM/Copa, and also SRT/RIST

Two mature bodies of prior art solve exactly this:

**Provisioned-path contribution:** SRT and RIST on managed links run at a fixed, operator-provisioned rate with FEC/ARQ and *no loss-based congestion control at all*. The entire broadcast contribution industry ships "rate floor + FEC on a path you've sized yourself" as the normal mode. A BDP-based floor on an administrator-provisioned remote-workstation path is the same design and is legitimate — provided there's a delay-based circuit breaker.

**Adaptive real-time media (WebRTC):** Google Congestion Control, SCReAM, and Copa all reached the same conclusion: for interactive media, **delay gradient is the primary congestion signal; loss is secondary and thresholded.** GCC concretely: loss below ~2% is *ignored* for rate purposes, 2–10% holds rate steady, only >10% triggers multiplicative decrease. The proposal — "don't reduce for loss within the FEC budget absent RTT growth" — is GCC's loss controller with the threshold tied to repair overhead. Meta runs Copa for live video for the same reason. So the "custom controller" isn't exotic; it's porting the RTC consensus into a Quinn `ControllerFactory` instead of an RTP stack.

## Recommended architecture

Three layers, one policy each:

### 1. A rate-target controller with a delay guard (replaces CUBIC via `ControllerFactory`)

The controller holds a target rate R = encoder target × 1.3 (FEC) × ~1.1 (protocol) + audio/control allowance, fed via a shared `Arc<AtomicU64>` updated when the toolbar changes — no KyProto API changes needed, since the factory is constructed in the kynet Quinn driver. It expresses itself as `window = R × smoothed_RTT × headroom (~1.25)`, which also sets Quinn's pacer, since Quinn derives pacing from window/RTT. Signals:

- Track `min_RTT` (windowed, ~10 s) and a queuing-delay estimate `sRTT − min_RTT`. Sustained queuing delay above a threshold (say 5–15 ms, tunable per deployment) → multiplicative rate reduction. This is the safety mechanism; it fires on real bottleneck queues even when loss is FEC-recoverable.
- Loss: ignore below the FEC-informed threshold (e.g., <½ of current repair overhead over a 1–2 s window); reduce when loss bursts exceed the recovery budget or coincide with delay growth or `is_persistent_congestion`.
- Delivery-rate sampling from acks (BBR-style bandwidth estimate): if acked throughput persistently sits below the send rate while loss is elevated, the path genuinely can't carry R — signal the application layer (see layer 3).

### 2. Frame-aware scheduling and dropping above Quinn — never let Quinn's datagram queue be the drop point

KyProto should admit symbols only as pacing budget allows and keep Quinn's queue nearly empty (it's a conveyor, not a buffer). When behind, drop at frame granularity, oldest first, *before* symbol submission — a whole RaptorQ object atomically. Shave repair symbols before source symbols when partially behind (losing repair costs margin; losing source can cost the frame). This alone converts "freeze" into "graceful frame drops" even before the controller changes, and it makes the `.215` experiment unnecessary: `send_datagram_wait()` was treating Quinn's queue as a backpressure signal, but the right amount of standing queue in Quinn is approximately zero.

### 3. Close the loop to the encoder and FEC

The controller's bandwidth estimate is the single bitrate authority. When sustained delivery < target, step the encoder down (Kyber already supports live bitrate changes) rather than letting any queue grow. And make repair overhead adaptive on receiver-reported loss (floor ~5–10% for burst protection): 30% flat at 150 Mbps is 45 Mbps of standing overhead that mostly *creates* packets, and with hundreds of symbols per frame the law of large numbers means needed overhead ≈ loss rate + modest margin.

## Answers to the 15 questions

**1. Eviction policy vs. frame-sized objects:** Fundamentally incompatible as a drop point for coded objects — newest-datagram-priority is fine for independent datagrams, catastrophic for symbols with intra-frame dependency. Don't make Quinn frame-aware; make KyProto the sole drop authority and keep Quinn's queue empty.

**2. Best algorithm for 100–200 Mbps, 0.5–2% random loss, no retransmit:** Delay-gradient-primary with thresholded loss (GCC-family semantics), implemented as a target-rate Quinn controller. Not CUBIC variants; not Quinn's BBR (the earlier experiment matched its known immaturity — bandwidth-sample instability and loss amplification).

**3. BDP floor on a provisioned private path:** Acceptable and industry-standard (SRT/RIST precedent), *as an explicit operator mode* with a delay circuit breaker and delivery-rate check. Document that it's a rate commitment, not fairness-seeking CC.

**4. Ignoring isolated loss under stable RTT + clear ECN + on-target delivery + within FEC budget:** Yes — those four jointly are the accepted signature of non-congestive loss. Caveats: use `sRTT − min_RTT` rather than raw RTT stability (deep buffers delay RTT movement); account for reverse-path/ack-delay effects (QUIC's ack_delay field helps); and periodically re-probe rather than assuming the classification is permanent.

**5. Copa/GCC/SCReAM/L4S vs. modifying CUBIC:** The former, decisively — beta tweaks keep the wrong model. L4S specifically depends on ECN, which ZeroTier breaks (see Q13). Borrow the algorithms; implement in Quinn rather than adopting another stack.

**6. Input/control priority on the shared connection:** With a rate-based controller running at ~1.25× headroom, cwnd starvation of tiny messages essentially disappears — that's the main fix. Additionally, ensure the driver's packet assembly services reliable stream data (input/control) ahead of video datagrams when both are pending, and reserve a small allowance in R. Verify Quinn's datagram-vs-stream interleaving order in the pinned version rather than assuming it.

**7. Repair vs. source symbols:** Same congestion accounting (bytes are bytes on the wire), different *drop* priority: repair symbols are the first thing shed under pressure, sent last within each frame's pacing window.

**8. Atomic vs. progressive admission:** Progressive admission with pacing is correct for latency (first symbols depart immediately). Atomicity belongs to the drop decision, not the admission.

**9. Pacing across the frame interval:** Yes, pace — bursting ~150 back-to-back datagrams per frame self-induces bottleneck queue loss and is likely a real contributor to loss clustering. But pace at the controller rate (which exceeds the average media rate by the headroom factor), so a frame drains in ~13 ms rather than being spread across the full 16.67 ms; the last symbol gates decode, so full-interval uniform pacing would add nearly a frame of latency.

**10. 30% flat repair:** Inappropriate at these rates. It's calibrated for worst case, paid always, and its packet count feeds the very loss-event frequency that collapses CUBIC. Adaptive 5–15% with receiver loss reports reclaims ~20% of path capacity — meaningful when there's almost no headroom at 150 Mbps.

**11. `ControllerFactory` adequacy:** Yes, cleanly. The `Controller` trait's `on_ack` (with RTT and byte counts), `on_congestion_event` (with persistence flag), and `window()` are sufficient for delay-gradient estimation, delivery-rate sampling, and rate-to-window mapping; dynamic target injection via shared atomics avoids KyProto changes entirely. The one thing missing is one-way delay (no SCReAM-style timestamps), so work with RTT minus ack delay — adequate in practice.

**12. Distinguishing congestion from non-congestive loss through ZeroTier:** No single reliable signal; use the ensemble — queuing-delay estimate against min-RTT, delivery-rate-vs-send-rate gap, and loss *pattern* (congestion loss clusters and correlates with delay peaks; random loss is temporally uniform — this can be computed cheaply). Add periodic brief probing above target to detect ceiling changes.

**13. ECN specifically:** Treat as unavailable. ZeroTier tunnels the inner IP packet inside UDP; underlay routers mark the *outer* header, and those marks die at decapsulation — they never reach Quinn. Inner-header ECN only reflects congestion at the tunnel endpoints themselves. Don't build the safety story on ECN.

**14. Multiple QUIC connections:** Don't. That trades one solvable scheduling problem for competing congestion controllers on the same path, more NAT/port surface, and divergence from the single-connection architecture — while the actual latency-isolation benefit is achievable with sender-side scheduling plus headroom (Q6).

**15. Dropping already-encoded frames:** Never drop arbitrary predictive frames. Best: propagate backpressure to capture, Kyber-style, so drops happen pre-encode. Where post-encode drops are unavoidable, use the mechanism Sunshine/Moonlight already possess — reference frame invalidation (NVENC supports invalidating references / LTR), so the next frame encodes against a still-valid reference; failing that, force an IDR or intra-refresh after any drop. This machinery exists in the codebase's ancestry; wiring queue-drop events to it is likely a small change.

## Suggested validation order

Do the layers in the order that isolates variables:

1. **Frame-aware drop/pacing layer alone (still on CUBIC):** the 0.5% test should shift from freeze to periodic clean frame drops, confirming the eviction amplification is gone.
2. **The controller:** the same test should show near-zero frame drops and rate holding at ~127 Mbps.
3. **A real congestion test:** a rate-limited tbf bottleneck below the target, not netem loss, to prove the delay guard backs off — that's the test that makes the design defensible.
4. **Burst-loss models:** re-run the netem test with burst/Gilbert–Elliott loss models, since i.i.d. loss is the friendliest case for per-frame FEC and the WAN won't be that polite.

One hard truth to keep in the requirements doc: at a 150 Mbps target on a ~200 Mbps path, no controller design gives meaningful margin. The controller can only be honest about that faster than CUBIC was destructive about it.
