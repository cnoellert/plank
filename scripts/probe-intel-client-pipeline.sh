#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 4)); then
  echo "usage: $0 BITSTREAM [FRAME_COUNT] [SUBMIT_LEAD_US] [serial|threaded]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_CLIENT_BUILD_DIR:-"${repo_dir}/build/client-qualification"}
protocol_dir=$(pkg-config --variable=pkgdatadir wayland-protocols)
xdg_xml="${protocol_dir}/stable/xdg-shell/xdg-shell.xml"
presentation_xml="${protocol_dir}/stable/presentation-time/presentation-time.xml"
commit_timing_xml="${protocol_dir}/staging/commit-timing/commit-timing-v1.xml"

mkdir -p "${build_dir}"
protocols=(xdg-shell presentation-time)
extra_cxx_flags=()
extra_protocol_objects=()
if [[ -f ${commit_timing_xml} ]]; then
  protocols+=(commit-timing-v1)
  extra_cxx_flags+=(-DCONNECT_HAVE_COMMIT_TIMING=1)
  extra_protocol_objects+=("${build_dir}/commit-timing-v1-protocol.o")
fi
for protocol in "${protocols[@]}"; do
  if [[ ${protocol} == xdg-shell ]]; then
    xml=${xdg_xml}
  elif [[ ${protocol} == presentation-time ]]; then
    xml=${presentation_xml}
  else
    xml=${commit_timing_xml}
  fi
  wayland-scanner client-header "${xml}" \
    "${build_dir}/${protocol}-client-protocol.h"
  wayland-scanner private-code "${xml}" \
    "${build_dir}/${protocol}-protocol.c"
  cc -O2 -Wall -Wextra -Wpedantic -Werror \
    $(pkg-config --cflags wayland-client) \
    -c "${build_dir}/${protocol}-protocol.c" \
    -o "${build_dir}/${protocol}-protocol.o"
done

c++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  -pthread "${extra_cxx_flags[@]}" \
  -I"${build_dir}" \
  "${repo_dir}/probes/video/connect-probe-client-pipeline.cpp" \
  "${build_dir}/xdg-shell-protocol.o" \
  "${build_dir}/presentation-time-protocol.o" \
  "${extra_protocol_objects[@]}" \
  $(pkg-config --cflags --libs gstreamer-1.0 gstreamer-app-1.0 \
    gstreamer-video-1.0 gstreamer-allocators-1.0 wayland-client wayland-egl \
    egl glesv2 libdrm) \
  -o "${build_dir}/connect-probe-client-pipeline"

"${build_dir}/connect-probe-client-pipeline" "$@"
