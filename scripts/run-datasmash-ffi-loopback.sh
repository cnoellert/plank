#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
crate_dir="$repo_root/protocol/datasmash-transport"
probe_source="$repo_root/probes/network/datasmash/ffi-loopback.c"
probe_tmp=$(mktemp -d /tmp/stationconnect-datasmash-ffi.XXXXXX)
probe_port=${STATIONCONNECT_DATASMASH_PORT:-47489}

cleanup() {
  rm -r "$probe_tmp"
}
trap cleanup EXIT INT TERM

if [[ ! "$probe_port" =~ ^[0-9]+$ ]] || (( probe_port < 1 || probe_port > 65535 )); then
  echo "invalid datasmash loopback port: $probe_port" >&2
  exit 2
fi

cargo build --locked --offline --release --manifest-path "$crate_dir/Cargo.toml"

cc -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -I"$crate_dir/include" \
  "$probe_source" \
  "$crate_dir/target/release/libstationconnect_datasmash_transport.a" \
  -ldl -lpthread -lm -lrt \
  -o "$probe_tmp/ffi-loopback"

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$probe_tmp/key.pem" \
  -out "$probe_tmp/cert.pem" \
  -days 1 -subj '/CN=localhost' >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(sha256sum "$probe_tmp/cert.der" | awk '{print $1}')

"$probe_tmp/ffi-loopback" \
  "127.0.0.1:$probe_port" \
  "127.0.0.1:$probe_port" \
  localhost \
  "$probe_tmp/cert.pem" \
  "$probe_tmp/key.pem" \
  "$certificate_hash"
