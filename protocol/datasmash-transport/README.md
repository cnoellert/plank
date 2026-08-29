# StationConnect datasmash transport library

This AGPL-3.0-or-later Rust library is the StationConnect-owned boundary around
the pinned Kyber/Kynet and Quinn transport. It is built only on the isolated
`datasmash` branch.

The public C ABI is
`include/stationconnect_datasmash.h`. A caller supplies copied endpoint
configuration, starts one opaque endpoint, waits or polls its state, and stops
and destroys it. Rust owns its Tokio runtime and worker threads; it does not
call back into Host or Client C++ while a C++ lock is held. Error text remains
owned by the endpoint and is copied into caller-provided storage.

The current Stage 3 slice establishes and holds two independently authenticated
QUIC connections on one UDP listener: `media` and `interaction`. The
certificate is pinned by SHA-256 and both roles use the same short-lived
session token. Duplicate, unknown, or mismatched roles are rejected.

For bookmarks that explicitly select datasmash, the `media` connection carries
the existing complete encrypted video/FEC packets as unreliable QUIC
DATAGRAMs. The Rust boundary adds only a small lane/sequence envelope; it does
not reinterpret RTP, FEC, or video encryption. Bounded queues discard the
oldest queued video packet rather than accumulate latency, and the C ABI
exports queue, byte, loss, and RTT counters. Audio, control, input, cursor, and
the initial video peer-association ping deliberately remain on their proven
legacy transports. Legacy remains the bookmark default.

Run the Rust and real C ABI checks with the pinned toolchain and offline Cargo
cache:

```bash
cargo test --locked --offline \
  --manifest-path protocol/datasmash-transport/Cargo.toml
cargo clippy --locked --offline \
  --manifest-path protocol/datasmash-transport/Cargo.toml \
  --all-targets -- -D warnings
scripts/run-datasmash-ffi-loopback.sh
```

The standalone saturation probe imports the library's role authentication,
which prevents the probe and product integration from drifting onto different
handshake formats. The FFI loopback also sends one split host packet through a
real QUIC connection and verifies byte-for-byte reconstruction at the client
ABI.
