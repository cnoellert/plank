#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
probe_dir="$repo_root/probes/network/plank-transport"
probe_binary="$probe_dir/target/release/plank-probe-plank_transport"
probe_port=${PLANK_TRANSPORT_PORT:-47489}
probe_duration=${PLANK_TRANSPORT_DURATION:-3}
probe_bitrate=${PLANK_TRANSPORT_BITRATE_BPS:-150000000}
probe_token=${PLANK_TRANSPORT_TOKEN:-plank-transport-loopback}
probe_tmp=$(mktemp -d /tmp/plank-transport.XXXXXX)
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
  echo 'plank_transport server did not become ready' >&2
  cat "$log_file" >&2
  return 1
}

start_server() {
  local log_file=$1
  local token=$2
  local duration=$3
  local bitrate=$4
  "$probe_binary" server "127.0.0.1:$probe_port" \
    "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$token" \
    "$duration" "$bitrate" >"$log_file" 2>&1 &
  server_pid=$!
  wait_for_server "$log_file"
}

expect_role_rejection() {
  local mode=$1
  local expected_error=$2
  local server_log="$probe_tmp/server-$mode.log"
  local client_log="$probe_tmp/client-$mode.log"

  start_server "$server_log" "$probe_token" 1 1000000
  if "$probe_binary" client "127.0.0.1:$probe_port" localhost \
    "$certificate_hash" "$probe_token" 1 "$mode" \
    >"$client_log" 2>&1; then
    echo "plank_transport client unexpectedly accepted role test: $mode" >&2
    exit 1
  fi
  if wait "$server_pid"; then
    echo "plank_transport server unexpectedly accepted role test: $mode" >&2
    exit 1
  fi
  server_pid=
  grep -q "$expected_error" "$server_log"
  echo "status=complete test=$mode-rejected"
}

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$probe_tmp/key.pem" \
  -out "$probe_tmp/cert.pem" \
  -days 1 -subj '/CN=localhost' >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(sha256sum "$probe_tmp/cert.der" | awk '{print $1}')

cargo build --locked --release --manifest-path "$probe_dir/Cargo.toml"

start_server "$probe_tmp/server.log" "$probe_token" "$probe_duration" "$probe_bitrate"

"$probe_binary" client "127.0.0.1:$probe_port" localhost \
  "$certificate_hash" "$probe_token" "$probe_duration" | tee "$probe_tmp/client.log"
wait "$server_pid"
server_pid=
cat "$probe_tmp/server.log"

grep -q '^status=complete role=client ' "$probe_tmp/client.log"
grep -q '^status=complete role=server ' "$probe_tmp/server.log"

# A QUIC connection with an invalid data-plane bearer token must be rejected
# before any logical lane becomes active.
start_server "$probe_tmp/server-negative.log" "$probe_token" 1 1000000
if "$probe_binary" client "127.0.0.1:$probe_port" localhost \
  "$certificate_hash" "${probe_token}-invalid" 1 \
  >"$probe_tmp/client-negative.log" 2>&1; then
  echo 'plank_transport client unexpectedly authenticated with an invalid token' >&2
  exit 1
fi
if wait "$server_pid"; then
  echo 'plank_transport server unexpectedly accepted an invalid token' >&2
  exit 1
fi
server_pid=
grep -q 'authentication token mismatch' "$probe_tmp/server-negative.log"
echo 'status=complete test=invalid-token-rejected'

# Connection roles are explicit authenticated protocol fields. Either arrival
# order is valid, while duplicate and unknown roles fail before lane startup.
start_server "$probe_tmp/server-interaction-first.log" "$probe_token" 1 1000000
"$probe_binary" client "127.0.0.1:$probe_port" localhost \
  "$certificate_hash" "$probe_token" 1 interaction-first \
  >"$probe_tmp/client-interaction-first.log"
wait "$server_pid"
server_pid=
grep -q '^status=complete role=client ' "$probe_tmp/client-interaction-first.log"
grep -q '^status=complete role=server ' "$probe_tmp/server-interaction-first.log"
echo 'status=complete test=interaction-first-accepted'

expect_role_rejection duplicate-media 'duplicate media connection role'
expect_role_rejection duplicate-interaction 'duplicate interaction connection role'
expect_role_rejection unknown-role 'unknown connection role 255'
expect_role_rejection mismatched-token 'authentication token mismatch'
