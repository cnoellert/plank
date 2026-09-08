# Video FEC loss telemetry

The toolbar and overlay use one receiver-side calculation. Both loss columns
use the same finalized RaptorQ objects and source-symbol denominator:

- Before: original source symbols absent when an object is finalized.
- After: those absent originals belonging to an object that was not fully
  reconstructed before the receiver retired it. A reconstructed object adds
  zero residual loss, even when repair symbols replaced missing originals.

Repair symbols are not included in either numerator or the denominator.
Duplicates do not increase the received-original count. Completed objects and
expired partial objects contribute exactly once. Sequence gaps alone do not
provide an object's size; entirely unseen objects cannot be included in this
packet metric. This is not an exact count of all IP/QUIC packets lost on the
path, nor a count of partially decoded internal RaptorQ blocks. A failed object
is unavailable to the video consumer even if some of its blocks decoded.

The counters are published as a coherent cumulative snapshot. The Client samples
one-second deltas, then displays the largest before and after percentage seen
over the preceding ten seconds. The two peaks may come from different seconds,
but after cannot exceed before. A fresh connection begins at N/A until a valid
interval exists. Counter resets and invalid snapshots establish a new baseline;
they must not produce negative percentages or spikes.

Frame-sequence gaps, sender omissions, late frames, decode errors and Client
render-queue drops are separate measurements. They must never supply the
`after FEC` column. In particular, 0% before FEC with a large after-FEC frame-gap
percentage was a units/denominator bug, not proof RaptorQ created packet loss.

The local transport C ABI is 13 because its stats structure gains a counter.
The wire format and negotiation are unchanged: a rebuilt Client can measure
an existing Host's traffic without a Host update. Each binary must link a
transport archive matching its own headers; package preflight and the C
loopback test reject the previous local ABI size.

Qualification includes deterministic RaptorQ source/repair loss, duplicate
originals, expiry, group retirement, cumulative counter resets, paired UI
percentages and real QUIC/FFI loopback. Synthetic loss tests are not WAN or
graphical playback acceptance.
