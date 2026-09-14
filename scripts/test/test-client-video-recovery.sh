#!/usr/bin/env bash
# Build-only test on linux-client-builder; no playback or installed package required.
set -euo pipefail
if [[ $# != 3 ]]; then
    echo "Usage: $0 ROOT_SOURCE COMMON_SOURCE EMPTY_OUTPUT" >&2
    exit 2
fi
root_source=$(realpath "$1")
common_source=$(realpath "$2")
output=$(realpath -m "$3")
mkdir "$output"
cc -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
    -ffunction-sections -fdata-sections -I"$common_source/src" \
    "$root_source/tests/session/native-video-recovery.c" \
    "$common_source/src/Platform.c" "$common_source/src/LinkedBlockingQueue.c" \
    -Wl,--gc-sections -pthread -o "$output/native-video-recovery"
"$output/native-video-recovery"
