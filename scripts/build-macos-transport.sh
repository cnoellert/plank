#!/bin/bash
# Build the existing transport unchanged on the dedicated development Mac.
# This is a qualification library, not an installable Host package.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo "Usage: $0 /absolute/source-worktree /absolute/build-directory" >&2
    exit 2
fi
source_root=$1
transport_build=$2
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ||
      $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires the authorized Apple Silicon development Mac, macOS/SDK 27+." >&2
    exit 2
fi
: "${PLANK_CARGO_ROOT:?Set the dedicated Mac Cargo cache path}"
: "${PLANK_RUSTUP_ROOT:?Set the dedicated Mac Rustup path}"
export CARGO_HOME="$PLANK_CARGO_ROOT" RUSTUP_HOME="$PLANK_RUSTUP_ROOT"
export PATH="$CARGO_HOME/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=27.0
# Rust's debug stripping can misalign proc-macro LINKEDIT on macOS 27.
# Keep compiler inputs intact; do not lower the deployment target or change Rust.
# See https://github.com/rust-lang/rust/issues/157750.
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C strip=none"
export SDKROOT
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
export CARGO_TARGET_DIR="$transport_build"
cd "$source_root"
test "$(rustc +1.89.0 --version | awk '{print $2}')" = 1.89.0
test -f protocol/plank-transport/Cargo.lock
test -f third_party/kyber-kymux/kyproto/Cargo.toml
test -f third_party/quinn-proto-0.11.17/PLANK-PATCH.md
git rev-parse HEAD
expected_kymux=$(git rev-parse HEAD:third_party/kyber-kymux)
test "$(git -C third_party/kyber-kymux rev-parse HEAD)" = "$expected_kymux"
printf 'Kymux: %s\n' "$expected_kymux"
cargo +1.89.0 build --locked --release --manifest-path protocol/plank-transport/Cargo.toml
cargo +1.89.0 test --locked --release --manifest-path protocol/plank-transport/Cargo.toml
shasum -a 256 "$transport_build/release/libplank_transport.a"

# Exercise the same real C ABI as Linux, with Apple platform link libraries.
# Bind loopback only; no product service or external authentication bypass.
probe_tmp=$(mktemp -d "$transport_build/ffi-loopback.XXXXXX")
trap 'rm -f "$probe_tmp/key.pem" "$probe_tmp/cert.pem" "$probe_tmp/cert.der" "$probe_tmp/native-ffi-loopback"; rmdir "$probe_tmp"' EXIT
xcrun clang -mmacosx-version-min=27.0 -std=c11 -Wall -Wextra -Wpedantic -Werror \
    -Iprotocol/plank-transport/include \
    "${PLANK_MACOS_LOOPBACK_SOURCE:-$source_root/probes/network/plank-transport/native-ffi-loopback.c}" \
    "$transport_build/release/libplank_transport.a" \
    -framework Security -framework SystemConfiguration -framework CoreFoundation \
    -lpthread -lm -o "$probe_tmp/native-ffi-loopback"
certificate_config=${PLANK_MACOS_LOOPBACK_CERT_CONFIG:-"$source_root/probes/macos/loopback-cert.cnf"}
test -f "$certificate_config"
# Explicit v3 avoids LibreSSL's v1 default; Rustls correctly rejects v1.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$certificate_config" \
    -keyout "$probe_tmp/key.pem" -out "$probe_tmp/cert.pem" >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(shasum -a 256 "$probe_tmp/cert.der")
certificate_hash=${certificate_hash%% *}
"$probe_tmp/native-ffi-loopback" 127.0.0.1:47489 127.0.0.1:47489 localhost \
    "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$certificate_hash"
"$probe_tmp/native-ffi-loopback" 127.0.0.1:47490 127.0.0.1:47490 localhost \
    "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$certificate_hash" "$probe_tmp/cert.der"
