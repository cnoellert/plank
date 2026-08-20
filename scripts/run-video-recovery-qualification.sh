#!/usr/bin/env bash

set -euo pipefail

if (($# > 4)); then
  echo "usage: $0 [OUTPUT_DIR] [FRAME_COUNT] [LOSS_FRAME] [OUTPUT_NAME]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_BUILD_DIR:-"${repo_dir}/build/qualification"}
output_dir=${1:-"${repo_dir}/artifacts/qualification/video"}
frame_count=${2:-600}
loss_frame=${3:-180}
output_name=${4:-${CONNECT_CAPTURE_OUTPUT:-DP-2}}
if [[ ! ${frame_count} =~ ^[0-9]+$ || ! ${loss_frame} =~ ^[0-9]+$ ]]; then
  echo "frame count and loss frame must be positive integers" >&2
  exit 2
fi
recovery_frame=$((loss_frame + 2))

if ((loss_frame < 1 || recovery_frame > frame_count)); then
  echo "loss frame must leave two later frames for recovery feedback" >&2
  exit 2
fi

active_session=$(loginctl show-seat seat0 --property=ActiveSession --value)
x11_user=$(loginctl show-session "${active_session}" --property=Name --value)
x11_uid=$(id -u "${x11_user}")
x11_display=${CONNECT_X11_DISPLAY:-:1}
x11_authority=${CONNECT_X11_AUTHORITY:-/run/user/${x11_uid}/gdm/Xauthority}
if [[ $(loginctl show-session "${active_session}" --property=Type --value) != x11 ]]; then
  echo "video recovery qualification requires the active X11 desktop" >&2
  exit 2
fi

for command_name in cmake ffprobe loginctl rg sha256sum sudo tee; do
  command -v "${command_name}" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 2
  }
done

mkdir -p "${output_dir}"
scratch_dir=$(mktemp -d --tmpdir stationconnect-recovery.XXXXXX)
cleanup() {
  rm -rf -- "${scratch_dir}"
}
trap cleanup EXIT

cmake --build "${build_dir}" --parallel --target connect-probe-video-pipeline
sudo -n loginctl unlock-session "${active_session}"

common=(
  --output "${output_name}"
  --frames "${frame_count}"
  --fps 60
  --queue-depth 1
  --split auto
  --intra-refresh-period 60
  --intra-refresh-count 30
  --single-slice-intra-refresh 1
  --require-changing
  --require-robustness
  --simulate-loss-frame "${loss_frame}"
)

invalidate_stream="${output_dir}/stationconnect-recovery-ref-invalidate.hevc"
invalidate_reference_stream="${output_dir}/stationconnect-recovery-ref-invalidate-reference.hevc"
invalidate_log="${scratch_dir}/invalidate.log"
sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
  XAUTHORITY="${x11_authority}" XDG_RUNTIME_DIR="/run/user/${x11_uid}" \
  "${build_dir}/connect-probe-video-pipeline" "${common[@]}" \
  --invalidate-delay-frames 2 --reference-frames 4 \
  --reference-bitstream "${invalidate_reference_stream}" \
  --bitstream "${invalidate_stream}" | tee "${invalidate_log}"
rg -q '^bitstream_loss_injection_gate=pass$' "${invalidate_log}"
rg -q '^reference_invalidation_gate=pass$' "${invalidate_log}"
rg -q '^integrated_2160p60_robustness_gate=pass$' "${invalidate_log}"

idr_stream="${output_dir}/stationconnect-recovery-forced-idr.hevc"
idr_log="${scratch_dir}/forced-idr.log"
sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
  XAUTHORITY="${x11_authority}" XDG_RUNTIME_DIR="/run/user/${x11_uid}" \
  "${build_dir}/connect-probe-video-pipeline" "${common[@]}" \
  --no-reference-invalidation --force-idr-frame "${recovery_frame}" \
  --bitstream "${idr_stream}" | tee "${idr_log}"
rg -q '^bitstream_loss_injection_gate=pass$' "${idr_log}"
rg -q '^forced_idr_submission_gate=pass$' "${idr_log}"
rg -q '^integrated_2160p60_robustness_gate=pass$' "${idr_log}"

expected_packets=$((frame_count - 1))
for stream in "${invalidate_stream}" "${idr_stream}"; do
  packets=$(ffprobe -v error -count_packets -select_streams v:0 \
    -show_entries stream=nb_read_packets -of csv=p=0 "${stream}")
  if [[ ${packets} != "${expected_packets}" ]]; then
    echo "bitstream packet count mismatch: expected ${expected_packets}, got ${packets}" >&2
    exit 1
  fi
  sha256sum "${stream}"
done

reference_packets=$(ffprobe -v error -count_packets -select_streams v:0 \
  -show_entries stream=nb_read_packets -of csv=p=0 \
  "${invalidate_reference_stream}")
if [[ ${reference_packets} != "${frame_count}" ]]; then
  echo "reference bitstream packet count mismatch: expected ${frame_count}, got ${reference_packets}" >&2
  exit 1
fi
sha256sum "${invalidate_reference_stream}"

echo "recovery_stream_frames=${expected_packets}"
echo "reference_invalidation_host_gate=pass"
echo "forced_idr_host_gate=pass"
echo "run the Intel VA-API decode and reference-pixel gates before qualification"
