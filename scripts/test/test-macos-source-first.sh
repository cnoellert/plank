#!/bin/bash
# Synthetic large-keyframe delivery comparison, not a WAN/playback test.
set -euo pipefail
if [[ $# != 4 || $(uname -s) != Darwin ]]; then
    echo 'Usage: test-macos-source-first.sh SOURCE EMPTY_OUTPUT BASELINE_ARCHIVE CANDIDATE_ARCHIVE' >&2
    exit 2
fi
source_root=$1; output=$2; baseline=$3; candidate=$4
mkdir "$output"
cd "$source_root"
for variant in baseline candidate; do
    archive=$baseline
    [[ $variant != candidate ]] || archive=$candidate
    shasum -a 256 "$archive"
    xcrun clang -mmacosx-version-min=27.0 -std=c11 -Wall -Wextra -Wpedantic -Werror \
        -DPLANK_LOOPBACK_VIDEO_BYTES=1100123 -Iprotocol/plank-transport/include \
        probes/network/plank-transport/native-ffi-loopback.c "$archive" \
        -framework Security -framework SystemConfiguration -framework CoreFoundation \
        -lpthread -lm -o "$output/$variant"
done
umask 077
tls=$(mktemp -d "$output/tls.XXXXXX")
trap 'rm -f "$tls/key.pem" "$tls/cert.pem" "$tls/cert.der"; rmdir "$tls"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config probes/macos/loopback-cert.cnf \
    -keyout "$tls/key.pem" -out "$tls/cert.pem" >/dev/null 2>&1
openssl x509 -in "$tls/cert.pem" -outform DER -out "$tls/cert.der"
cert_hash=$(shasum -a 256 "$tls/cert.der"); cert_hash=${cert_hash%% *}
for trial in {1..20}; do
    for variant in baseline candidate; do
        "$output/$variant" 127.0.0.1:47495 127.0.0.1:47495 localhost \
            "$tls/cert.pem" "$tls/key.pem" "$cert_hash" > "$output/$variant-$trial.log" 2>&1
        printf '%s trial=%s ' "$variant" "$trial"
        sed -n '/^native_video_complete_us=/p' "$output/$variant-$trial.log"
    done
done
