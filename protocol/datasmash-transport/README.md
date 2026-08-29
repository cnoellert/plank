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
the existing complete encrypted video/FEC and audio/FEC packets as unreliable
QUIC DATAGRAMs. The Rust boundary adds only a small lane/sequence envelope; it
does not reinterpret RTP, FEC, media encryption, or FEC. Bounded per-lane
queues discard the oldest same-lane media packet rather than accumulate
latency, with strict audio-before-video dequeue priority.

ABI version 4 also provides a bounded client-to-Host reliable control-record
queue on the independent `interaction` connection. It preserves the complete
encrypted GameStream control packet and never evicts an accepted command: a
full client queue applies explicit backpressure and a full Host queue fails the
connection closed. Product wiring begins with one low-frequency StationConnect
control message before input, Wacom, or cursor traffic moves. The initial peer
association pings and setup protocols deliberately remain on their proven
legacy paths. Legacy remains the bookmark default.

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
handshake formats. The FFI loopback sends video, audio, and a client-to-Host
reliable control packet through real QUIC connections and verifies byte-for-byte
reconstruction at the opposite C ABI.
