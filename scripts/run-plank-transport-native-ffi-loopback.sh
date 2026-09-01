#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
crate_dir="$repo_root/protocol/plank-transport"
probe_source="$repo_root/probes/network/plank-transport/native-ffi-loopback.c"
probe_tmp=$(mktemp -d /tmp/plank-native-ffi.XXXXXX)
probe_port=${PLANK_TRANSPORT_PORT:-47489}
target_dir=${CARGO_TARGET_DIR:-"$crate_dir/target"}
trap 'rm -rf -- "$probe_tmp"' EXIT

cargo build --locked --offline --release --manifest-path "$crate_dir/Cargo.toml"
cc -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -I"$crate_dir/include" \
  "$probe_source" \
  "$target_dir/release/libplank_transport.a" \
  -ldl -lpthread -lm -lrt \
  -o "$probe_tmp/native-ffi-loopback"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=localhost' \
  -keyout "$probe_tmp/key.pem" \
  -out "$probe_tmp/cert.pem" >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(sha256sum "$probe_tmp/cert.der")
certificate_hash=${certificate_hash%% *}

"$probe_tmp/native-ffi-loopback" \
  "127.0.0.1:$probe_port" \
  "127.0.0.1:$probe_port" \
  localhost \
  "$probe_tmp/cert.pem" \
  "$probe_tmp/key.pem" \
  "$certificate_hash"

profile_port=$((probe_port + 1))
"$probe_tmp/native-ffi-loopback" \
  "127.0.0.1:$profile_port" \
  "127.0.0.1:$profile_port" \
  localhost \
  "$probe_tmp/cert.pem" \
  "$probe_tmp/key.pem" \
  "$certificate_hash" \
  "$probe_tmp/cert.der"
