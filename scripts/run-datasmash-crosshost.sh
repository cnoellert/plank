#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
probe_dir="$repo_root/probes/network/datasmash"
probe_binary="$probe_dir/target/release/connect-probe-datasmash"
probe_client=${STATIONCONNECT_DATASMASH_CLIENT:?Set STATIONCONNECT_DATASMASH_CLIENT for your test environment}
probe_client_ip=${STATIONCONNECT_DATASMASH_CLIENT_IP:-192.0.2.250}
probe_server_ip=${STATIONCONNECT_DATASMASH_SERVER_IP:-192.0.2.104}
probe_port=${STATIONCONNECT_DATASMASH_PORT:-47489}
probe_duration=${STATIONCONNECT_DATASMASH_DURATION:-10}
probe_bitrate=${STATIONCONNECT_DATASMASH_BITRATE_BPS:-150000000}
probe_loss=${STATIONCONNECT_DATASMASH_LOSS_PERCENT:-0}
probe_loss_pattern=${STATIONCONNECT_DATASMASH_LOSS_PATTERN:-random}
probe_token=stationconnect-datasmash-crosshost
probe_tmp=$(mktemp -d /tmp/stationconnect-datasmash-crosshost.XXXXXX)
remote_binary=/tmp/stationconnect-datasmash-probe-$$
server_pid=
nft_table_created=false

for numeric_value in "$probe_port" "$probe_duration" "$probe_bitrate" "$probe_loss"; do
  if [[ ! "$numeric_value" =~ ^[0-9]+$ ]]; then
    echo "datasmash numeric setting is invalid: $numeric_value" >&2
    exit 2
  fi
done
if (( probe_port < 1 || probe_port > 65535 || probe_duration < 1 || probe_bitrate < 1 || probe_loss > 100 )); then
  echo 'datasmash port, duration, bitrate, or loss percentage is out of range' >&2
  exit 2
fi
if [[ "$probe_loss_pattern" != random && "$probe_loss_pattern" != periodic-burst ]]; then
  echo 'datasmash loss pattern must be random or periodic-burst' >&2
  exit 2
fi

cleanup() {
  if [[ "$nft_table_created" == true ]]; then
    sudo -n nft delete table inet stationconnect_datasmash_test 2>/dev/null || true
  fi
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  ssh -o BatchMode=yes "$probe_client" "unlink '$remote_binary'" 2>/dev/null || true
  rm -r "$probe_tmp"
}
trap cleanup EXIT INT TERM

if sudo -n nft list table inet stationconnect_datasmash_test >/dev/null 2>&1; then
  echo 'refusing to reuse the existing inet stationconnect_datasmash_test nft table' >&2
  exit 1
fi

cargo build --locked --release --manifest-path "$probe_dir/Cargo.toml"
scp -q "$probe_binary" "$probe_client:$remote_binary"
ssh -o BatchMode=yes "$probe_client" "chmod 0700 '$remote_binary'"

local_hash=$(sha256sum "$probe_binary" | awk '{print $1}')
remote_hash=$(ssh -o BatchMode=yes "$probe_client" "sha256sum '$remote_binary'" | awk '{print $1}')
if [[ "$local_hash" != "$remote_hash" ]]; then
  echo 'cross-host probe binary hash mismatch' >&2
  exit 1
fi

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$probe_tmp/key.pem" \
  -out "$probe_tmp/cert.pem" \
  -days 1 -subj '/CN=localhost' >/dev/null 2>&1
openssl x509 -in "$probe_tmp/cert.pem" -outform DER -out "$probe_tmp/cert.der"
certificate_hash=$(sha256sum "$probe_tmp/cert.der" | awk '{print $1}')

"$probe_binary" server "0.0.0.0:$probe_port" \
  "$probe_tmp/cert.pem" "$probe_tmp/key.pem" "$probe_token" \
  "$probe_duration" "$probe_bitrate" >"$probe_tmp/server.log" 2>&1 &
server_pid=$!

for _ in $(seq 1 100); do
  if grep -q '^status=listening ' "$probe_tmp/server.log"; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    sed -n '1,200p' "$probe_tmp/server.log" >&2
    exit 1
  fi
  sleep 0.05
done
if ! grep -q '^status=listening ' "$probe_tmp/server.log"; then
  echo 'datasmash server did not become ready' >&2
  exit 1
fi

if (( probe_loss > 0 )); then
  sudo -n nft add table inet stationconnect_datasmash_test
  nft_table_created=true
  sudo -n nft 'add chain inet stationconnect_datasmash_test output { type filter hook output priority filter; policy accept; }'
  if [[ "$probe_loss_pattern" == random ]]; then
    sudo -n nft add rule inet stationconnect_datasmash_test output \
      ip daddr "$probe_client_ip" udp sport "$probe_port" \
      numgen random mod 100 '<' "$probe_loss" drop
  else
    sudo -n nft add rule inet stationconnect_datasmash_test output \
      ip daddr "$probe_client_ip" udp sport "$probe_port" \
      numgen inc mod 100 '<' "$probe_loss" drop
  fi
fi

ssh -o BatchMode=yes "$probe_client" \
  "'$remote_binary' client '$probe_server_ip:$probe_port' localhost '$certificate_hash' '$probe_token' '$probe_duration'" \
  | tee "$probe_tmp/client.log"
wait "$server_pid"
server_pid=
sed -n '1,200p' "$probe_tmp/server.log"

grep -q '^status=complete role=client ' "$probe_tmp/client.log"
grep -q '^status=complete role=server ' "$probe_tmp/server.log"
echo "status=complete test=crosshost loss_percent=$probe_loss loss_pattern=$probe_loss_pattern binary_sha256=$local_hash"
