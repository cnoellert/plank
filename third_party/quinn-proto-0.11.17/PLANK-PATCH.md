# Vendored Quinn backport

This directory contains crates.io `quinn-proto 0.11.17` with PLANK's narrow
DATAGRAM accounting, MTU-boundary and telemetry repairs described below, plus
the opt-in controller feature described later.

The source crate is pinned by `Cargo.lock`. Its original MIT and Apache-2.0
licenses and crates.io VCS provenance are retained in the vendored directory.

The send-buffer backport corrects two defects present in the released code:

- send-buffer pruning now includes the memory needed by the new DATAGRAM;
- pruning relies on `DatagramBuffer::pop_front()` as the sole payload-byte
  decrement instead of decrementing the counter twice.

It also rejects a single DATAGRAM that cannot fit in the configured send
buffer and adds a focused regression test. The first and third changes are
adapted from upstream Quinn commits
`88c4e96d119e1ada071356986415de8294a89d65` and
`c50f83bc4f5df16aa71d05e2d20e8f2b04ae4f62`. The double-decrement correction
is specific to the `DatagramBuffer` refactor shipped in 0.11.17.

MTU recovery now preserves DATAGRAM payloads **equal to** the permitted maximum
(`<=`, consistent with send validation), not just smaller payloads. Black-hole
detection can revisit an unchanged fixed MTU; the old strict comparison could
discard a frame's queued source and repair symbols even though every datagram
still fit. Valid equality must also survive an actual MTU reduction. Unit tests
cover equality, below/above bounds, repeated recovery, empty payloads, retained
order and byte/memory accounting. Genuine MTU discards have separate
`mtu_dropped_datagrams`/`mtu_dropped_payload_bytes` telemetry; they must not be
mistaken for send-queue capacity evictions. No MTU policy, window, FEC percentage,
queue limit, ordering deadline or pacer behavior is changed.

With `plank-telemetry`, `Connection::stats()` now copies diagnostic fields into
an owned `ConnectionStats::plank_telemetry` snapshot instead of formatting and
writing stderr while Quinn holds its connection-state mutex. Snapshot capture
does not allocate, log, start threads or alter protocol counters. The Kynet
adapter's `quinn-telemetry` feature forwards this feature and consumes the
snapshot only after the public Quinn `stats()` call returns and releases its
guard. Keep the adapter and this vendor change together.

The adapter uses one process-wide logging thread and an eight-snapshot bounded
queue. It performs a non-waiting enqueue, with no synchronous logging fallback.
Slow/full/failed logging can discard diagnostic samples, never block media on
disk I/O or accumulate an unbounded log backlog. Session teardown does not join
the writer; final samples are best-effort. Existing log fields, queue/MTU-drop
counters and the effective-pacing calculation are retained; live RTT/loss
statistics do not depend on successful logging. Feature-disabled builds contain
neither the snapshot fields nor logging worker. No transport ABI or wire change.

Vendor tests check owned snapshots and real queue/drain accounting. The product
`protocol/plank-transport/tests/quinn-telemetry.rs` includes the actual adapter
logger so its blocked/failed-sink, queue-bound and output-format tests run with
the product's lockfile and patched Quinn, not a separately resolved Kyber build.

Linux Host packaging runs `connection::datagrams::plank_tests` and the
feature-enabled telemetry snapshot test using this crate's own locked test
dependencies and an archive never linked into the product.
Hosted bootstrap fetches those inputs before the offline build; the dependency
cache includes this manifest and lockfile. The real native transport loss matrix
also runs three times for each Host rate policy, stopping on the first failure.

The additional `plank-bbr-default` feature makes Quinn's experimental BBR
controller the default only when PLANK explicitly enables it. Without that
feature, the vendored crate retains upstream's CUBIC default. This narrow hook
exists because Kyber 0.28.0 does not expose Quinn's congestion controller in
its public connection options; it is not a proposed product API.

Both the production transport crate and its standalone probes consume this one
canonical copy. Do not create a second probe-local vendor tree.

Remove this override only after Kyber resolves to a released Quinn version
that contains equivalent fixes and passes the PLANK 5% and 10% loss
qualification tests.
