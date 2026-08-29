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

The current Stage 2 foundation establishes and holds two independently
authenticated QUIC connections on one UDP listener: `media` and
`interaction`. The certificate is pinned by SHA-256 and both roles use the
same short-lived session token. Duplicate, unknown, or mismatched roles are
rejected. No product payload is carried through this ABI yet, and the existing
StationConnect data plane remains the product default.

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
which prevents the probe and eventual product integration from drifting onto
different handshake formats.
