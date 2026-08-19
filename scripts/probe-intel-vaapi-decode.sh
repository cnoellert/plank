#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 3)); then
  echo "usage: $0 BITSTREAM [FRAME_COUNT] [RENDER_NODE]" >&2
  exit 2
fi

bitstream=$1
frame_count=${2:-9000}
render_node=${3:-/dev/dri/renderD128}

if [[ ! -r "${bitstream}" ]]; then
  echo "bitstream is not readable: ${bitstream}" >&2
  exit 2
fi
if [[ ! -e "${render_node}" ]]; then
  echo "VA-API render node is unavailable: ${render_node}" >&2
  exit 2
fi

export LIBVA_DRIVER_NAME=${LIBVA_DRIVER_NAME:-iHD}
vainfo_output=$(vainfo --display drm --device "${render_node}" 2>&1)
echo "${vainfo_output}"
if ! rg -q 'VAProfileHEVCMain444_10[[:space:]]*:[[:space:]]*VAEntrypointVLD' \
    <<<"${vainfo_output}"; then
  echo 'vaapi_hevc_main444_10_decode_capability=fail' >&2
  exit 1
fi
echo 'vaapi_hevc_main444_10_decode_capability=pass'

metadata=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,r_frame_rate \
  -of default=noprint_wrappers=1 "${bitstream}")
echo "${metadata}"
for expected in codec_name=hevc profile=Rext width=3840 height=2160 \
  pix_fmt=gbrp10le color_range=pc color_space=gbr \
  color_transfer=iec61966-2-1 color_primaries=bt709 r_frame_rate=60/1; do
  if [[ "${metadata}" != *"${expected}"* ]]; then
    echo "input metadata gate failed: missing ${expected}" >&2
    exit 1
  fi
done

started_ns=$(date +%s%N)
ffmpeg -v error -hwaccel vaapi -hwaccel_device "${render_node}" \
  -hwaccel_output_format vaapi -i "${bitstream}" -frames:v "${frame_count}" \
  -f null -
finished_ns=$(date +%s%N)
elapsed_ms=$(((finished_ns - started_ns) / 1000000))
decode_fps=$(awk -v frames="${frame_count}" -v ms="${elapsed_ms}" \
  'BEGIN { printf "%.2f", frames * 1000 / ms }')

echo "decoded_frames=${frame_count}"
echo "decode_elapsed_ms=${elapsed_ms}"
echo "decode_fps=${decode_fps}"
if awk -v fps="${decode_fps}" 'BEGIN { exit !(fps >= 60.0) }'; then
  echo 'vaapi_2160p60_decode_throughput_gate=pass'
else
  echo 'vaapi_2160p60_decode_throughput_gate=fail' >&2
  exit 1
fi
