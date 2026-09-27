#!/usr/bin/env bash
# Headless source-timestamp tests. No audio devices, network or user session.
set -euo pipefail
client=${1:?Client source root}
build=${2:?Test output directory}
common_library=${3:?Exact candidate common-C static library}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
mkdir -p "$build"
"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -pthread \
    -I"$client/app/streaming" \
    "$client/tests/avsynccontroller/test_audio_timestamps.cpp" \
    "$client/app/streaming/avsynccontroller.cpp" -o "$build/audio-timestamp-observer"
"$build/audio-timestamp-observer"
libraries=()
if [[ $(uname -s) == Linux ]]; then libraries=(-lcrypto -lpthread -lm); fi
"${CC:-cc}" -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
    -I"$client/moonlight-common-c/moonlight-common-c/src" \
    -I"$root/protocol/plank-transport/include" \
    "$client/moonlight-common-c/moonlight-common-c/tests/audio-timestamps.c" \
    "$common_library" "${libraries[@]}" -o "$build/audio-timestamp-callback"
"$build/audio-timestamp-callback"
python3 "$root/tests/audio/test-source-audio-timing.py"
echo 'audio_timestamp_gate=pass live_sync_acceptance=not-performed'
