#!/usr/bin/env bash

set -euo pipefail

if (($# < 2 || $# > 4)); then
  echo "usage: $0 INVALIDATE_STREAM IDR_STREAM [FRAME_COUNT] [IDR_OUTPUT_FRAME]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
invalidate_stream=$1
idr_stream=$2
frame_count=${3:-599}
idr_output_frame=${4:-181}
if [[ ! ${frame_count} =~ ^[0-9]+$ ||
      ! ${idr_output_frame} =~ ^[0-9]+$ ]]; then
  echo "frame count and IDR output frame must be positive integers" >&2
  exit 2
fi
if ((frame_count < 1 || idr_output_frame < 1)); then
  echo "frame count and IDR output frame must be positive integers" >&2
  exit 2
fi

"${repo_dir}/scripts/probe-intel-vaapi-decode.sh" \
  "${invalidate_stream}" "${frame_count}"
"${repo_dir}/scripts/probe-intel-vaapi-decode.sh" \
  "${idr_stream}" "${frame_count}"

mapfile -t invalidate_keys < <(
  ffprobe -v error -select_streams v:0 -show_packets \
    -show_entries packet=flags -of csv=p=0 "${invalidate_stream}" |
    awk '/K/ { print NR }'
)
mapfile -t idr_keys < <(
  ffprobe -v error -select_streams v:0 -show_packets \
    -show_entries packet=flags -of csv=p=0 "${idr_stream}" |
    awk '/K/ { print NR }'
)

if ((${#invalidate_keys[@]} != 1)) || [[ ${invalidate_keys[0]} != 1 ]]; then
  echo "invalidation stream unexpectedly contains a recovery IDR" >&2
  exit 1
fi
if ((${#idr_keys[@]} != 2)) || [[ ${idr_keys[0]} != 1 ]] ||
    [[ ${idr_keys[1]} != "${idr_output_frame}" ]]; then
  echo "forced-IDR packet position does not match the requested recovery frame" >&2
  exit 1
fi

echo "reference_invalidation_intel_decode_gate=pass"
echo "forced_idr_intel_decode_gate=pass"
echo "forced_idr_output_frame=${idr_output_frame}"
