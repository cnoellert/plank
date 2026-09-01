#!/usr/bin/env bash

set -euo pipefail

if (($# < 3 || $# > 6)); then
  echo "usage: $0 REFERENCE_STREAM LOSS_STREAM LOSS_FRAME [FRAME_COUNT] [MAX_HEALING_FRAMES] [RENDER_NODE]" >&2
  exit 2
fi

reference_stream=$1
loss_stream=$2
loss_frame=$3
frame_count=${4:-600}
max_healing_frames=${5:-120}
render_node=${6:-/dev/dri/renderD128}

for value_name in loss_frame frame_count max_healing_frames; do
  value=${!value_name}
  if [[ ! ${value} =~ ^[0-9]+$ ]] || ((value < 1)); then
    echo "${value_name} must be a positive integer" >&2
    exit 2
  fi
done
if ((loss_frame >= frame_count)); then
  echo "loss frame must precede the final reference frame" >&2
  exit 2
fi
for stream in "${reference_stream}" "${loss_stream}"; do
  if [[ ! -r ${stream} ]]; then
    echo "bitstream is not readable: ${stream}" >&2
    exit 2
  fi
done
if [[ ! -e ${render_node} ]]; then
  echo "VA-API render node is unavailable: ${render_node}" >&2
  exit 2
fi
for command_name in awk grep gst-inspect-1.0 gst-launch-1.0 mktemp wc; do
  command -v "${command_name}" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 2
  }
done
for element in h265parse vah265dec vapostproc checksumsink; do
  gst-inspect-1.0 "${element}" >/dev/null
done

scratch_dir=$(mktemp -d --tmpdir plank-recovery-pixels.XXXXXX)
cleanup() {
  rm -rf -- "${scratch_dir}"
}
trap cleanup EXIT

hash_stream() {
  local input_stream=$1
  local output_file=$2
  local error_file=$3
  GST_DEBUG_NO_COLOR=1 LIBVA_DRIVER_NAME=iHD \
    gst-launch-1.0 -q filesrc "location=${input_stream}" ! h265parse ! \
      vah265dec ! 'video/x-raw(memory:VAMemory),format=Y410' ! \
      vapostproc ! 'video/x-raw,format=Y410' ! checksumsink hash=sha256 \
      >"${output_file}.raw" 2>"${error_file}"
  grep -E '^[0-9]+:[0-9:.]+ [0-9a-f]{64}$' "${output_file}.raw" >"${output_file}"
}

reference_hashes="${scratch_dir}/reference.sha256"
loss_hashes="${scratch_dir}/loss.sha256"
hash_stream "${reference_stream}" "${reference_hashes}" "${scratch_dir}/reference.err"
hash_stream "${loss_stream}" "${loss_hashes}" "${scratch_dir}/loss.err"

reference_count=$(wc -l <"${reference_hashes}")
loss_count=$(wc -l <"${loss_hashes}")
if ((reference_count != frame_count)); then
  echo "reference decoded-frame count mismatch: expected ${frame_count}, got ${reference_count}" >&2
  exit 1
fi
if ((loss_count != frame_count - 1)); then
  echo "loss decoded-frame count mismatch: expected $((frame_count - 1)), got ${loss_count}" >&2
  exit 1
fi

comparison=$(awk -v loss_frame="${loss_frame}" '
  NR == FNR { reference[++reference_count] = $2; next }
  { loss[++loss_count] = $2 }
  END {
    for (frame_index = 1; frame_index < loss_frame; frame_index++) {
      if (loss[frame_index] != reference[frame_index]) {
        pre_loss_mismatches++
      }
    }
    for (frame_index = loss_frame; frame_index <= loss_count; frame_index++) {
      source_frame = frame_index + 1
      if (loss[frame_index] != reference[source_frame]) {
        post_loss_mismatches++
        last_mismatch_source_frame = source_frame
      }
    }
    first_persistent_match = last_mismatch_source_frame == 0 ? loss_frame + 1 : last_mismatch_source_frame + 1
    printf "pre_loss_mismatches=%d\n", pre_loss_mismatches
    printf "post_loss_mismatches=%d\n", post_loss_mismatches
    printf "last_mismatch_source_frame=%d\n", last_mismatch_source_frame
    printf "first_persistent_match_source_frame=%d\n", first_persistent_match
    printf "healing_frames=%d\n", first_persistent_match - loss_frame
  }
' "${reference_hashes}" "${loss_hashes}")
echo "${comparison}"

pre_loss_mismatches=$(awk -F= '$1 == "pre_loss_mismatches" { print $2 }' <<<"${comparison}")
healing_frames=$(awk -F= '$1 == "healing_frames" { print $2 }' <<<"${comparison}")
if ((pre_loss_mismatches != 0)); then
  echo 'pre_loss_pixel_identity_gate=fail' >&2
  exit 1
fi
echo 'pre_loss_pixel_identity_gate=pass'
if ((healing_frames > max_healing_frames)); then
  echo 'reference_invalidation_pixel_healing_gate=fail' >&2
  exit 1
fi
echo 'reference_invalidation_pixel_healing_gate=pass'
