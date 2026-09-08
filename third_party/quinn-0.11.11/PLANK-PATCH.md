# Bounded datagram submission experiment

Exact crates.io Quinn 0.11.11, upstream VCS
`a7499b8439e393a6299330111d9c8564cd96c464` (path `quinn`). Source archive SHA-256:
`0c1a41e437b6bbd489372cd4971de128e85c855f56c57f283d20ff016cf7c0a8`.
Retain MIT/Apache licenses and original Cargo/VCS metadata.

The optional `plank-datagram-batch` feature adds one connection API:
`send_datagram_batch(&[Bytes])`. Each lock accepts at most sixteen already-ready
packets, then wakes the existing driver. No wait-for-fill, packet merging,
queue enlargement, MTU change, congestion-controller change or new worker.
Packet errors/oldest-datagram eviction are identical to `send_datagram`; a
partly successful batch still wakes the driver before returning its error.

Only the explicitly selected macOS Host experiment calls the API. Ordinary
single-packet sends remain byte-identical upstream code. This is the Quinn
async connection wrapper, distinct from our existing `quinn-proto` repair.
Keep both pinned sources synchronized through the root transport Cargo lock.
Do not claim reduced latency from submission time alone: compare complete-frame
receive and concurrent interaction delivery against .53 before live acceptance.
