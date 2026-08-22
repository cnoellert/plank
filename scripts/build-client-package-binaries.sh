#!/usr/bin/env bash

set -euo pipefail

if (($# < 2 || $# > 3)); then
  echo "usage: $0 MOONLIGHT_SOURCE_DIR FFMPEG_WORK_DIR [BUILD_DIR]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=$(realpath -- "$1")
ffmpeg_work_dir=$(realpath -- "$2")
build_dir=$(realpath -m -- "${3:-${repo_dir}/build/package-client}")
ffmpeg_prefix="${ffmpeg_work_dir}/install"

for command_name in git make pkg-config qmake6 readelf realpath rg; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

[[ -f ${source_dir}/moonlight-qt.pro ]] || {
  echo "Moonlight source tree is unavailable: ${source_dir}" >&2
  exit 1
}
if [[ -n $(git -C "$source_dir" status --porcelain) ]]; then
  echo "Moonlight source tree is dirty; refusing a package build" >&2
  exit 1
fi
if [[ -d ${build_dir} && -n $(find "$build_dir" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
  echo "package build directory is not empty: ${build_dir}" >&2
  exit 1
fi

export PKG_CONFIG_PATH="${ffmpeg_prefix}/lib/pkgconfig"
export LD_LIBRARY_PATH="${ffmpeg_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ $(pkg-config --modversion libavcodec) == 63.* ]] || {
  echo "FFmpeg 9 libavcodec pkg-config metadata was not selected" >&2
  exit 1
}

mkdir -p "$build_dir"
(
  cd "$build_dir"
  qmake6 "$source_dir" CONFIG+=release \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${source_dir}=../src" \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${source_dir}=../src"
  make -j"$(nproc)"
)

client_binary="${build_dir}/app/moonlight"
[[ -x ${client_binary} ]] || {
  echo "Moonlight package binary was not produced" >&2
  exit 1
}
dynamic_section=$(readelf -d "$client_binary")
for soname in libavcodec.so.63 libavutil.so.61 libswscale.so.10; do
  rg -q "Shared library: \[${soname//./\\.}\]" <<<"$dynamic_section" || {
    echo "Moonlight did not link the required FFmpeg 9 SONAME: ${soname}" >&2
    exit 1
  }
done
"${repo_dir}/scripts/audit-package-runtime.sh" \
  "$client_binary" "${ffmpeg_prefix}/lib"
echo "client_binary=${client_binary}"
echo "client_package_binary_gate=pass"
