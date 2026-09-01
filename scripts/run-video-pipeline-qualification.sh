#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}
bitstream=${1:-/tmp/plank-identity-gbr.hevc}
output_name=${PLANK_CAPTURE_OUTPUT:-DP-2}

active_session=$(loginctl show-seat seat0 --property=ActiveSession --value)
x11_user=$(loginctl show-session "${active_session}" --property=Name --value)
x11_uid=$(id -u "${x11_user}")
x11_display=${PLANK_X11_DISPLAY:-:1}
x11_authority=${PLANK_X11_AUTHORITY:-/run/user/${x11_uid}/gdm/Xauthority}

if [[ $(loginctl show-session "${active_session}" --property=Type --value) != x11 ]]; then
  echo 'video pipeline qualification requires the active X11 desktop' >&2
  exit 2
fi

cmake --build "${build_dir}" --parallel --target plank-probe-video-pipeline

# This test is intentionally visible. It unlocks the active session and displays a
# software-rendered 2160p60 pattern so NvFBC observes real changing pixels.
sudo -n loginctl unlock-session "${active_session}"
sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
  XAUTHORITY="${x11_authority}" XDG_RUNTIME_DIR="/run/user/${x11_uid}" \
  SDL_RENDER_DRIVER=software \
  timeout 20s ffplay -hide_banner -nostats -loglevel warning \
  -f lavfi -i 'testsrc2=size=3840x2160:rate=60' -fs -an &
pattern_pid=$!

cleanup() {
  if kill -0 "${pattern_pid}" 2>/dev/null; then
    kill "${pattern_pid}" 2>/dev/null || true
    wait "${pattern_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

sleep 1
sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
  XAUTHORITY="${x11_authority}" XDG_RUNTIME_DIR="/run/user/${x11_uid}" \
  "${build_dir}/plank-probe-video-pipeline" \
  --output "${output_name}" --frames 600 --fps 60 --queue-depth 1 \
  --split auto --intra-refresh-period 60 --intra-refresh-count 30 \
  --single-slice-intra-refresh 1 --require-changing \
  --require-robustness --bitstream "${bitstream}"

metadata=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,pix_fmt,color_range,color_space,color_transfer,color_primaries,r_frame_rate \
  -of default=noprint_wrappers=1 "${bitstream}")
echo "${metadata}"

for expected in codec_name=hevc profile=Rext width=3840 height=2160 \
  pix_fmt=gbrp10le color_range=pc color_space=gbr \
  color_transfer=iec61966-2-1 color_primaries=bt709 r_frame_rate=60/1; do
  if [[ "${metadata}" != *"${expected}"* ]]; then
    echo "bitstream metadata gate failed: missing ${expected}" >&2
    exit 1
  fi
done

ffmpeg -v error -hwaccel none -i "${bitstream}" -frames:v 600 -f null -
echo 'video_pipeline_bitstream_decode_gate=pass'
