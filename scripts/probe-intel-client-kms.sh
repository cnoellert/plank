#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 4)); then
  echo "usage: $0 BITSTREAM [FRAME_COUNT] [SUBMIT_LEAD_US] [DRM_DEVICE]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_CLIENT_BUILD_DIR:-"${repo_dir}/build/client-qualification"}
mkdir -p "${build_dir}"

c++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  "${repo_dir}/probes/video/connect-probe-client-kms.cpp" \
  $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-app-1.0 \
    gstreamer-video-1.0 gstreamer-allocators-1.0 libdrm) \
  -o "${build_dir}/connect-probe-client-kms"

if [[ ${CONNECT_BUILD_ONLY:-0} == 1 ]]; then
  exit 0
fi

"${build_dir}/connect-probe-client-kms" "$@"
