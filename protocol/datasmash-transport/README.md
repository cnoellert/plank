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

ABI version 7 adds the certificate-gated pre-session boundary. An active
legacy-stage launch may still use the exact fingerprint and one-use token, but
the true single-port setup mode starts with only a reliable KyProto data
endpoint. The Client receives the peer leaf certificate, validates it against
the StationConnect certificate profile, and explicitly approves it before any
application queue is enabled. PAM, ownership, display, and launch setup then
run on that reliable endpoint. Video, audio, and input endpoints are registered
on the same QUIC connection only after both peers authorize the session.

The version-1 `LAUNCH_RESPONSE` JSON payload carries the exact accepted
`video_format`, `host_feature_flags`, and
`reference_frame_invalidation` capability, plus the Opus sample rate, channel
count, stream counts, packet duration, and channel mapping. The Client must
install those host capabilities together with the codec/audio values before it
starts common-c. Missing local-cursor support or malformed capability values
fail the connection; they never fall back to stale RTSP-derived state.

Complete Annex-B
frames use `VideoProtocol::UnreliableFec`, raw Opus uses
`AudioProtocol::UnreliableFec`, input uses KyProto's reliable input protocol,
and non-input control uses its reliable data protocol. Kyber owns media
packetization, RaptorQ, ordering, QUIC, and protocol statistics; StationConnect
does not add GameStream RTP, media AES, or Reed-Solomon on this path.

Each outbound lane has an independent wake-up and bounded queue, preventing a
notification for one protocol from being consumed by another. Complete video
metadata is carried in a small StationConnect prefix inside the RaptorQ object
and removed after reconstruction. The older two-connection packet-tunnel ABI
remains temporarily available only while the native product cutover is being
qualified on the isolated branch; it will be deleted after the live matrix
passes. Legacy remains the bookmark default until then.

Run the Rust and real C ABI checks with the pinned toolchain and offline Cargo
cache:

```bash
cargo test --locked --offline \
  --manifest-path protocol/datasmash-transport/Cargo.toml
cargo clippy --locked --offline \
  --manifest-path protocol/datasmash-transport/Cargo.toml \
  --all-targets -- -D warnings
scripts/run-datasmash-ffi-loopback.sh
scripts/run-datasmash-native-loopback.sh
scripts/run-datasmash-native-ffi-loopback.sh
```

The native C loopback verifies exact-fingerprint and certificate-profile trust,
pre-session data with media/input blocked, explicit same-connection promotion,
a 192-KiB key frame and metadata, raw Opus, Wacom-like input, and reliable data
in both directions through real encrypted KyProto endpoints. The standalone saturation probe remains useful historical
evidence for the tunneled implementation, but its split-connection and BBR
results are not assumed for the new one-connection native baseline.
