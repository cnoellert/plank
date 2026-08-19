#!/usr/bin/env bash

set -euo pipefail

if (($# > 1)); then
  echo "usage: $0 [FRAME_COUNT]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_CLIENT_BUILD_DIR:-"${repo_dir}/build/client-qualification"}
protocol_dir=$(pkg-config --variable=pkgdatadir wayland-protocols)
xml="${protocol_dir}/stable/xdg-shell/xdg-shell.xml"

mkdir -p "${build_dir}"
wayland-scanner client-header "${xml}" \
  "${build_dir}/xdg-shell-client-protocol.h"
wayland-scanner private-code "${xml}" \
  "${build_dir}/xdg-shell-protocol.c"
cc -O2 -Wall -Wextra -Wpedantic -Werror \
  $(pkg-config --cflags wayland-client) \
  -c "${build_dir}/xdg-shell-protocol.c" \
  -o "${build_dir}/xdg-shell-protocol.o"
c++ -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror \
  -I"${build_dir}" \
  "${repo_dir}/probes/video/connect-probe-wayland-xr30.cpp" \
  "${build_dir}/xdg-shell-protocol.o" \
  $(pkg-config --cflags --libs wayland-client wayland-egl egl glesv2 libdrm) \
  -o "${build_dir}/connect-probe-wayland-xr30"

"${build_dir}/connect-probe-wayland-xr30" "${1:-180}"
