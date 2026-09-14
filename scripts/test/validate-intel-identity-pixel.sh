#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)); then
  echo "usage: $0 BITSTREAM FRAME_NUMBER" >&2
  exit 2
fi

bitstream=$1
frame=$2
if [[ ! ${frame} =~ ^[1-9][0-9]*$ ]]; then
  echo "FRAME_NUMBER must be a positive integer" >&2
  exit 2
fi

frame_index=$((frame - 1))
reference=$(ffmpeg -loglevel error -i "${bitstream}" \
  -vf "select='eq(n,${frame_index})',crop=1:1:iw/2:ih/2,format=gbrp10le" \
  -frames:v 1 -f rawvideo - | od -An -tu2)
read -r reference_g reference_b reference_r <<<"${reference}"

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
probe_output=$("${repo_dir}/scripts/test/probe-intel-vaapi-dmabuf.sh" \
  "${bitstream}" "${frame}" "${frame}")
actual_r=$(awk -F= '$1 == "output_r10" {print $2}' <<<"${probe_output}")
actual_g=$(awk -F= '$1 == "output_g10" {print $2}' <<<"${probe_output}")
actual_b=$(awk -F= '$1 == "output_b10" {print $2}' <<<"${probe_output}")

printf '%s\n' "${probe_output}"
printf 'reference_r10=%s\nreference_g10=%s\nreference_b10=%s\n' \
  "${reference_r}" "${reference_g}" "${reference_b}"
if [[ ${actual_r} != "${reference_r}" || ${actual_g} != "${reference_g}" ||
      ${actual_b} != "${reference_b}" ]]; then
  echo 'identity_pixel_comparison=fail'
  exit 1
fi
echo 'identity_pixel_comparison=pass'
