#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 4)); then
  echo "usage: $0 BITSTREAM [FRAME_COUNT] [SAMPLE_FRAME] [RENDER_NODE]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_CLIENT_BUILD_DIR:-"${repo_dir}/build/client-qualification"}
binary="${build_dir}/connect-probe-vaapi-dmabuf"

mkdir -p "${build_dir}"
c++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  "${repo_dir}/probes/video/connect-probe-vaapi-dmabuf.cpp" \
  $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-app-1.0 \
    gstreamer-video-1.0 gstreamer-allocators-1.0 egl gbm glesv2 libdrm) \
  -o "${binary}"

"${binary}" "$@"
