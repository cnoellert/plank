#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 2)); then
  echo "usage: $0 MOONLIGHT_APP_DIR [WORK_DIR]" >&2
  exit 2
fi

ffmpeg_version=9.0.1
ffmpeg_sha256=cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
ffmpeg_url="https://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.xz"
moonlight_app_dir=$(realpath -m -- "$1")
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(realpath -m -- "${2:-${repo_dir}/build/client-ffmpeg-${ffmpeg_version}}")
archive="${work_dir}/ffmpeg-${ffmpeg_version}.tar.xz"
source_dir="${work_dir}/ffmpeg-${ffmpeg_version}"
build_dir="${work_dir}/build"
install_dir="${work_dir}/install"
bundle_dir="${moonlight_app_dir}/lib"

for command in curl make nasm pkg-config sha256sum tar; do
  if ! command -v "${command}" >/dev/null; then
    echo "Required command is unavailable: ${command}" >&2
    exit 1
  fi
done

mkdir -p "${work_dir}"
if [[ ! -f ${archive} ]]; then
  curl --fail --location --output "${archive}" "${ffmpeg_url}"
fi
printf '%s  %s\n' "${ffmpeg_sha256}" "${archive}" | sha256sum --check --status

if [[ ! -x ${source_dir}/configure ]]; then
  tar -xJf "${archive}" -C "${work_dir}"
fi
mkdir -p "${build_dir}" "${install_dir}"

(
  cd -- "${build_dir}"
  "${source_dir}/configure" \
    --prefix="${install_dir}" \
    --disable-doc \
    --disable-debug \
    --disable-static \
    --enable-shared \
    --enable-vaapi \
    --enable-libdrm
  make -j"$(nproc)"
  make install
)

mkdir -p "${bundle_dir}/licenses/ffmpeg"
for library in libavcodec libavutil libswscale libswresample; do
  cp -a "${install_dir}/lib/${library}.so"* "${bundle_dir}/"
done
cp -a "${source_dir}/COPYING.LGPLv2.1" "${source_dir}/COPYING.LGPLv3" \
  "${bundle_dir}/licenses/ffmpeg/"

echo "FFmpeg ${ffmpeg_version} installed in ${install_dir}"
echo "Runtime libraries bundled in ${bundle_dir}"
echo "Build Moonlight with PKG_CONFIG_PATH=${install_dir}/lib/pkgconfig"
