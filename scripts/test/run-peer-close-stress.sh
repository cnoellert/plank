#!/usr/bin/env bash
# Repeated real C ABI qualification; no retries or relaxed closure deadline.
set -euo pipefail
[[ $# -ge 2 && $# -le 3 && $1 == /* && $2 == /* ]] || {
  echo 'usage: run-peer-close-stress.sh TRANSPORT_ARCHIVE NEW_OUTPUT [ITERATIONS]' >&2
  exit 2
}
archive=$1
output=$2
iterations=${3:-20}
[[ $iterations =~ ^[1-9][0-9]*$ && $iterations -le 1000 ]] || exit 2
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test -f "$archive"
mkdir "$output"
trap 'rm -f "$output/key.pem" "$output/cert.pem" "$output/cert.der"' EXIT
if [[ $(uname -s) = Darwin ]]; then
  compiler=(xcrun clang -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-27.0}")
  libraries=(-framework Security -framework SystemConfiguration -framework CoreFoundation -lpthread -lm)
  digest=(shasum -a 256)
else
  compiler=(cc)
  libraries=(-ldl -lpthread -lm -lrt)
  digest=(sha256sum)
fi
"${compiler[@]}" -std=c11 -Wall -Wextra -Wpedantic -Werror \
  -I"$root/protocol/plank-transport/include" \
  "$root/probes/network/plank-transport/native-ffi-loopback.c" "$archive" \
  "${libraries[@]}" -o "$output/probe"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -config "$root/probes/macos/loopback-cert.cnf" \
  -keyout "$output/key.pem" -out "$output/cert.pem" >/dev/null 2>&1
openssl x509 -in "$output/cert.pem" -outform DER -out "$output/cert.der"
hash=$("${digest[@]}" "$output/cert.der")
hash=${hash%% *}
"${digest[@]}" "$archive" "$output/probe"
for ((trial=1; trial<=iterations; trial++)); do
  for mode in fingerprint profile; do
    extra=()
    [[ $mode != profile ]] || extra=("$output/cert.der")
    if ! "$output/probe" 127.0.0.1:47489 127.0.0.1:47489 localhost \
        "$output/cert.pem" "$output/key.pem" "$hash" ${extra[@]+"${extra[@]}"} \
        > "$output/$trial-$mode.log" 2>&1; then
      echo "FAIL trial=$trial trust=$mode; see $output/$trial-$mode.log" >&2
      exit 1
    fi
  done
  echo "peer_close_trial=$trial/$iterations fingerprint=pass setup_promotion=pass"
done
echo "peer_close_stress=pass cases=$((iterations*2))"
