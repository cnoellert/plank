# StationConnect Kyber / RaptorQ congestion control

**Subject:** High-bitrate UnreliableFec over Quinn DATAGRAM under recoverable random loss  
**Date:** 2026-08-31  
**Context:** StationConnect native Kyber path, single QUIC connection, 10–150 Mbps encoder targets, 30% RaptorQ, ZeroTier WAN, 1344-byte QUIC payload

---

## Executive conclusion

The diagnosis in the problem brief is correct. RaptorQ is not failing. CUBIC is starving the sender so symbols never leave the host.

The 0.5% client-ingress loss is a rounding error against 30% repair. The freeze is from **local eviction** of unsent symbols after CUBIC multiplies the congestion window by 0.7 on every recovery epoch.

At ~195 Mbps and 1344-byte payloads that is ~18,000 datagrams/s. Independent 0.5% loss is ~90 losses/s. QUIC batches some of those into one epoch, but not enough: CUBIC never finishes the cubic climb back to the previous \(W_{max}\) before the next cut. The encoder keeps producing ~98 Mbps + 30% FEC; Quinn admits 16–63 Mbps; the 1 MiB DATAGRAM buffer then throws away older symbols. RaptorQ cannot reconstruct packets that were never transmitted.

That is the whole failure mode. The rest is policy.

---

## What not to do

**`send_datagram_wait` is the wrong long-term answer.** It stops eviction but does not restore send rate. Backlog moves into the 4-frame encoded queue, couples video congestion onto audio on the same connection, and still leaves CUBIC in charge of capacity. Revert the unpushed `.215` change (`0e62e84` / `2e426dd`).

**Do not raise the DATAGRAM send buffer, socket buffers, CUBIC initial window, MTU, or static FEC% as the fix.** Those change when you notice the mismatch, not the mismatch.

**Do not ship Quinn’s stock BBR as-is.** The earlier trial already showed inflated reported loss, higher RTT, and unstable bandwidth estimates. Quinn’s BBR is still experimental; BBRv3 work in that tree has had pacing and inflight accounting bugs. A model-based controller is the right *class*, not that binary.

**Do not open a second QUIC connection** just to isolate input. Two controllers fighting on the same ZeroTier path is worse than one coherent controller that keeps a BDP-sized window so 100-byte input frames are never queued behind a video burst.

---

## Recommended policy: one FEC-aware target-rate controller

Stay on native Kyber + UnreliableFec + one QUIC connection. Replace CUBIC for this data plane with a Quinn `ControllerFactory` that treats the toolbar bitrate as the intended operating point and treats isolated loss as repairable noise until stronger congestion evidence appears.

This is the clean hook. Quinn already constructs the controller from `TransportConfig.congestion_controller_factory`. You do not need to fork `send_datagram` semantics or KyProto’s RaptorQ object model.

### Intended wire rate

```text
wire_target = encoder_target
            × (1 + raptorq_overhead)      # 1.30 today
            × proto_tax                   # KyProto + QUIC + UDP + ZT; measure, ~1.08–1.15
            + audio_and_control_allowance # small constant, e.g. 2–5 Mbps
```

The slider today is encoder-only. The controller must use **wire** rate. If the path cannot carry `wire_target`, the encoder target is wrong; do not pretend congestion control can invent capacity. At 150 Mbps encoder you already need ≳195 Mbps plus headers. On a ~200 Mbps practical ceiling that config has no headroom even on a clean path.

### Window and pacing

\[
\mathrm{cwnd} = \mathrm{wire\_target} \times \mathrm{srtt} \times G
\]

with \(G \approx 1.25\)–\(1.5\), a floor of \(\mathrm{wire\_target} \times \mathrm{min\_rtt} \times 1.1\), and **pacing_rate = wire_target**.

CUBIC’s job is “probe until loss.” This product’s job is “hold BDP for a provisioned rate, pace, and only leave that point when the path proves it cannot.” That is acceptable on an administrator-set private workstation path. It is not acceptable as a general Internet CUBIC replacement, and it should not be presented as one.

### When to ignore loss

Ignore a congestion event (do not apply \(\beta = 0.7\)) when **all** of these hold:

- Loss in the last 1–2 RTTs is well under the FEC budget (for example `< 0.4 × 30%` → under ~12%; 0.5% is nowhere close).
- `srtt - min_rtt` is below a small queue budget (start at 10–20 ms; tune on ZeroTier).
- No ECN-CE increase (if ECN validation succeeds).
- Quinn’s outgoing DATAGRAM occupancy is not growing.
- Measured delivery rate stays near `wire_target`.

This is the same idea GCC already uses for interactive video: 0–2% loss is “not congestion, keep or raise rate.” SCReAM and BBR do the same with different signals (delay / delivery rate; BBR’s default loss threshold is 2% per round). The rQUIC result is the warning: if FEC packets still cut cwnd when lost, FEC buys nothing at the transport layer.

### When to cut

Cut rate or window when any of these appear:

- Persistent congestion (RFC 9002 meaning).
- Sustained RTT inflation above the queue budget.
- ECN-CE (if the path preserves it).
- Delivery rate stays below target for several RTTs **and** delay is rising.
- Loss bursts that exceed what 30% RaptorQ can rebuild (not 0.5% random).
- Persistent DATAGRAM-buffer growth — that is sender-side proof the controller is admitting more than the path or the pacer can take.

On a cut, reduce `wire_target` (and tell the encoder), not just cwnd. Otherwise the encoder vs transport mismatch returns.

ZeroTier makes RTT and ECN imperfect: batching, encapsulation, and possible ECN bleaching. Treat delay as a *guard*, not as a high-resolution AQM. Measure whether ECT markings survive Host → ZeroTier → WAN → Client before leaning on ECN. If they do not, the delay + delivery-rate + queue-occupancy triple is enough for this product.

---

## Application rules that belong in the same policy

A custom controller without these still loses frames.

### 1. Pace symbols across the frame interval

Do not generate hundreds of source+repair symbols and shove them into Quinn in one burst. At 60 fps that burst is the entire 16.7 ms budget arriving in microseconds. Even a correct cwnd then looks like a micro-burst; GSO/pacing issues in Quinn have already shown tail-drop from exactly this pattern. Spread symbols uniformly over the frame period (or a slightly tighter budget so the last repair still arrives inside the client’s ~50 ms reconstruct window).

### 2. Keep `send_datagram()`, but never fill the DATAGRAM buffer

Newest-datagram eviction **is** incompatible with a multi-symbol RaptorQ object. Quinn does not know frame boundaries, so it punches random holes in an object and the receiver sees “loss” far above the network loss. The fix is not a frame-aware Quinn queue. The fix is: cwnd + pacing such that the 1 MiB buffer stays nearly empty. If admission control is ever needed, drop a **whole unsent frame** at KyProto/StationConnect, never an arbitrary older symbol.

### 3. Drop before encode, not mid-GOP in the 4-slot FFI queue

`VIDEO_SEND_CAPACITY = 4` replacing an already-encoded predictive frame is how reference breaks happen. Kyber Desktop drops capture-side for this reason. StationConnect joins after NVENC/x264, so either:

- drop captured frames before encode when the controller signals “below target / queue rising,” or
- only replace a complete frame when the encoder can emit an IDR/GDR.

Do not keep the wait-on-datagram experiment that turns transport delay into encoded-frame replacement.

### 4. One bitrate authority

Toolbar → `wire_target` → controller floor/pacer → encoder. When the path cannot hold the selected rate, turn the slider down in software. A 150 Mbps request on a 160 Mbps path with 30% FEC is an operator error the controller should surface, not paper over.

### 5. Leave 30% FEC for now

0.5% loss does not need more repair. More repair means more packets, which only hurts while CUBIC is still in the path. After the new controller is in, measure whether 15–20% is enough on the qualified ZeroTier WAN; that is a later tuning pass, not the first patch.

---

## Answers to the numbered questions

1. **Eviction vs frame-sized objects.** Incompatible if the buffer is allowed to fill. Make the buffer stay empty (pace + window). Frame-aware dropping is a fallback at KyProto, not a Quinn change.

2. **Best CC class for 100–200 Mbps interactive + 30% FEC + 0.5–2% random loss.** Delay/delivery-rate controller with a target-rate floor, not loss-based AIMD. SCReAM / GCC / Copa / BBR-like. Not CUBIC, not “CUBIC with \(\beta = 0.95\).”

3. **BDP floor on a provisioned private path.** Yes, if gated by delay/queue/ECN and if exceeding the real bottleneck lowers the encoder target. A hard floor with no safety valve is a congestion-unaware sender.

4. **Ignore isolated loss under stable RTT, clear ECN, on-target delivery, in-budget loss.** Yes. That is the entire point of application FEC. Document it as “random-loss exemption,” not “no congestion control.”

5. **Copa / GCC / SCReAM / L4S vs patched CUBIC.** Any of those families beats patched CUBIC. Practical choice here: a small custom Quinn controller with SCReAM/GCC logic (target rate, delay budget, loss exemption, encoder feedback). Full SCReAM or L4S only pays off if ECN survives ZeroTier; verify that first.

6. **Input/audio on the shared connection.** Keep them on the same QUIC connection. Reliable streams for input already bypass DATAGRAM eviction. The controller must keep cwnd ≥ BDP so control bytes are not sitting behind a video burst. Do not block `send_datagram` on video.

7. **Different accounting for repair vs source.** No, not for congestion. A lost repair is still a packet on the wire. Optionally schedule source symbols first inside the frame so the reconstruct window starts earlier; that is scheduling, not a second cwnd.

8. **Atomic frame vs progressive symbols.** Progressive admission + uniform pacing. Atomic admission recreates the burst.

9. **Pace across 16.67 ms.** Yes. This is as important as the controller.

10. **Is 30% right at 100–150 Mbps?** It is more than enough for 0.5% random loss and currently harmful only because each extra packet is another CUBIC event. After CC is fixed, consider lowering it to cut wire rate and leave headroom under a 200 Mbps ceiling.

11. **`ControllerFactory` without invading KyProto.** Yes. That is the structurally clean change. Keep UnreliableFec and `send_datagram()`. Wire toolbar bitrate into the factory/config the controller reads each frame or on slider change.

12. **Congestion vs ZeroTier WAN loss.** Combine: min-RTT baseline, queue delay, delivery rate vs target, DATAGRAM queue occupancy, loss burstiness (isolated vs runs), ECN if valid. Random loss is sparse and delay-stable. Real congestion is delay-up and/or delivery-down together.

13. **Does QUIC expose enough telemetry?** Enough for this: RTT estimator, loss events, ECN counters (if validated), bytes in flight, controller metrics (`congestion_window`, `pacing_rate`, `bandwidth_estimate`). You also need application counters: DATAGRAM evictions, symbols queued, frames reconstructed vs skipped. Quinn does not know FEC budget; the StationConnect controller must.

14. **Multiple connections.** No, unless input latency is still coupled after the window stays at BDP. Two CUBIC/BBR instances on one overlay is not isolation.

15. **Encoded-frame drops.** Drop pre-encode, or drop only when the reference can be refreshed. The 4-deep post-encode queue is a latency cap, not a congestion-control primitive.

---

## Suggested implementation order

1. Revert `send_datagram_wait` if it is still local.
2. Add a StationConnect `ControllerFactory` with target-rate window, pacer, random-loss exemption, delay/queue guard. Leave KyProto RaptorQ untouched.
3. Pace symbol submission over the frame interval in the Quinn driver or immediately above it.
4. Plumb encoder-target changes into the controller; plumb “path below target” back to the encoder / slider.
5. Replay the exact IFB 0.5% client-ingress test at 98 and 150 Mbps. Success criteria: evictions ≈ 0, reconstruct success ≈ clean-path, RTT within a few ms of baseline, input still immediate.
6. Then a real-congestion test: netem rate limit below `wire_target`. Success criteria: encoder comes down, queues do not grow, no freeze-from-eviction.
7. Only then consider FEC% and ECN/L4S.

---

## Success criteria (from the original brief)

- UnreliableFec remains active.
- No video retransmission is introduced.
- 0.5% independent random loss is recovered without visible freezing.
- Latency remains close to the clean-link baseline.
- The congestion window remains sufficient for the selected FEC-inclusive bitrate.
- Real congestion still causes a controlled and safe response.
- Input and audio remain responsive.
- No large buffering delay develops.
- The implementation is one coherent transport policy rather than multiple interacting workarounds.

---

## One-sentence policy

Hold the provisioned BDP, pace the FEC object, let RaptorQ eat random holes, and only leave the target when the path or the sender queue says the target is a lie. CUBIC cannot express that sentence. A small Quinn `Controller` can.
