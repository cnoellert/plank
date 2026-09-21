// SPDX-License-Identifier: AGPL-3.0-or-later
#![cfg(feature = "quinn-telemetry")]

// Dependency unit tests are not run by `cargo test` in this crate. Exercise the
// actual adapter logger with the product lockfile and patched Quinn, without
// resolving Kyber's separate workspace or introducing another test copy.
#[path = "../../../third_party/kyber-kymux/kynet/src/driver/quinn_telemetry.rs"]
mod quinn_telemetry;
