#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
probe_dir="$repo_root/probes/network/datasmash"
probe_binary="$probe_dir/target/release/connect-probe-datasmash"
probe_port=${STATIONCONNECT_DATASMASH_PORT:-47489}
probe_duration=${STATIONCONNECT_DATASMASH_DURATION:-3}
probe_bitrate=${STATIONCONNECT_DATASMASH_BITRATE_BPS:-150000000}
probe_token=${STATIONCONNECT_DATASMASH_TOKEN:-stationconnect-datasmash-loopback}
probe_tmp=$(mktemp -d /tmp/stationconnect-datasmash.XXXXXX)
server_pid=

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -r "$probe_tmp"
}
trap cleanup EXIT INT TERM

wait_for_server() {
  local log_file=$1
  for _ in $(seq 1 100); do
    if grep -q '^status=listening ' "$log_file"; then
      return 0
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
      cat "$log_file" >&2
      return 1
    fi
    sleep 0.05
  done
  echo 'datasmash server did not become ready' >&2
  cat "$log_file" >&2
  return 1
}

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$probe_tmp/key.pem" \
  -out "$probe_tmp/cert.pem" \
  -days 1 -subj '/CN=localhost' >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(sha256sum "$probe_tmp/cert.der" | awk '{print $1}')

cargo build --locked --release --manifest-path "$probe_dir/Cargo.toml"

"$probe_binary" server "127.0.0.1:$probe_port" \
  "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$probe_token" \
  "$probe_duration" "$probe_bitrate" >"$probe_tmp/server.log" 2>&1 &
server_pid=$!
wait_for_server "$probe_tmp/server.log"

"$probe_binary" client "127.0.0.1:$probe_port" localhost \
  "$certificate_hash" "$probe_token" "$probe_duration" | tee "$probe_tmp/client.log"
wait "$server_pid"
server_pid=
cat "$probe_tmp/server.log"

grep -q '^status=complete role=client ' "$probe_tmp/client.log"
grep -q '^status=complete role=server ' "$probe_tmp/server.log"

# A QUIC connection with an invalid data-plane bearer token must be rejected
# before any logical lane becomes active.
"$probe_binary" server "127.0.0.1:$probe_port" \
  "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$probe_token" 1 1000000 \
  >"$probe_tmp/server-negative.log" 2>&1 &
server_pid=$!
wait_for_server "$probe_tmp/server-negative.log"
if "$probe_binary" client "127.0.0.1:$probe_port" localhost \
  "$certificate_hash" "${probe_token}-invalid" 1 \
  >"$probe_tmp/client-negative.log" 2>&1; then
  echo 'datasmash client unexpectedly authenticated with an invalid token' >&2
  exit 1
fi
if wait "$server_pid"; then
  echo 'datasmash server unexpectedly accepted an invalid token' >&2
  exit 1
fi
server_pid=
grep -q 'authentication token mismatch' "$probe_tmp/server-negative.log"
echo 'status=complete test=invalid-token-rejected'
