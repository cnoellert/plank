#!/usr/bin/env bash

set -euo pipefail

size=${CONNECT_NVENC_SIZE:-3840x2160}
rate=${CONNECT_NVENC_RATE:-60}
frames=${CONNECT_NVENC_FRAMES:-120}
output=$(mktemp --tmpdir connect-nvenc.XXXXXX.h265)
trap 'rm -f -- "${output}"' EXIT

command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null

start_seconds=${SECONDS}
ffmpeg -hide_banner -loglevel error -nostdin -y \
  -f lavfi -i "testsrc2=size=${size}:rate=${rate}" \
  -frames:v "${frames}" -an -vf format=yuv444p16le \
  -c:v hevc_nvenc -profile:v rext -preset:v p1 -tune:v ull \
  -rc:v constqp -qp:v 24 -bf 0 -rc-lookahead 0 -zerolatency 1 -delay 0 \
  -g 2147483647 -intra-refresh 1 -single-slice-intra-refresh 1 \
  -f hevc "${output}"

properties=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,pix_fmt,width,height,r_frame_rate \
  -of default=noprint_wrappers=1 "${output}")

echo "${properties}"
echo "encoded_frames=${frames}"
echo "encoded_bytes=$(stat -c %s "${output}")"
echo "elapsed_seconds=$((SECONDS - start_seconds))"

grep -qx 'codec_name=hevc' <<<"${properties}"
grep -qx 'profile=Rext' <<<"${properties}"
grep -qx 'pix_fmt=yuv444p10le' <<<"${properties}"
grep -qx "r_frame_rate=${rate}/1" <<<"${properties}"
echo 'nvenc_hevc_rext_10bit_444_with_intra_refresh=pass'

