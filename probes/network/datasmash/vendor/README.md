# Vendored Quinn backport

`quinn-proto-0.11.17/` is the unmodified crates.io source for
`quinn-proto 0.11.17`, except for the narrow StationConnect DATAGRAM
send-buffer accounting backport in `src/connection/datagrams.rs`.

The source crate is pinned by `Cargo.lock`. Its original MIT and Apache-2.0
licenses and crates.io VCS provenance are retained in the vendored directory.

The backport corrects both defects present in the released 0.11.17 code:

- send-buffer pruning now includes the memory needed by the new DATAGRAM;
- pruning relies on `DatagramBuffer::pop_front()` as the sole payload-byte
  decrement instead of decrementing the counter twice.

It also rejects a single DATAGRAM that cannot fit in the configured send
buffer and adds a focused regression test. The first and third changes are
adapted from upstream Quinn commits
`88c4e96d119e1ada071356986415de8294a89d65` and
`c50f83bc4f5df16aa71d05e2d20e8f2b04ae4f62`. The double-decrement correction
is specific to the `DatagramBuffer` refactor shipped in 0.11.17.

The additional `stationconnect-bbr-default` feature makes Quinn's experimental
BBR controller the default only when the Datasmash probe explicitly enables
it. Without that feature, the vendored crate retains upstream's CUBIC default.
This narrow hook exists because Kyber 0.28.0 does not expose Quinn's congestion
controller in its public connection options; it is not a proposed product API.

Remove this override only after Kyber resolves to a released Quinn version
that contains equivalent fixes and passes the StationConnect 5% and 10% loss
qualification tests.
