#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 3)); then
  echo "usage: $0 CLIENT_SSH [CLIENT_SINK_ID] [TONE_SECONDS]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
client=$1
client_sink_id=${2:-}
tone_seconds=${3:-4}
host_sink=${PLANK_AUDIO_SINK:-sink-sunshine-stereo}
tone_hz=997
control_hz=3000

[[ $tone_seconds =~ ^[1-9][0-9]?$ ]] || {
  echo "tone duration must be an integer from 1 through 99 seconds" >&2
  exit 2
}

for command_name in awk ffmpeg pactl rg scp ssh; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

ssh_options=(-o BatchMode=yes)
if [[ -n ${PLANK_SSH_CONFIG:-} ]]; then
  ssh_options+=(-F "$PLANK_SSH_CONFIG")
fi
if [[ -n ${PLANK_SSH_KNOWN_HOSTS:-} ]]; then
  ssh_options+=(-o StrictHostKeyChecking=yes -o "UserKnownHostsFile=${PLANK_SSH_KNOWN_HOSTS}")
fi

if [[ -z $client_sink_id ]]; then
  client_sink_id=$(ssh "${ssh_options[@]}" "$client" \
    "wpctl inspect @DEFAULT_AUDIO_SINK@" | awk '
      NR == 1 && $1 == "id" {
        gsub(/,/, "", $2)
        print $2
        exit
      }
    ')
fi
[[ $client_sink_id =~ ^[0-9]+$ ]] || {
  echo "unable to resolve a numeric client sink ID" >&2
  exit 1
}

pactl list short sinks | awk '{print $2}' | rg -Fxq "$host_sink" || {
  echo "host audio sink is unavailable: ${host_sink}" >&2
  exit 1
}
pactl list source-outputs | rg -q 'application\.name = "sunshine"' || {
  echo "Sunshine is not actively recording host audio" >&2
  exit 1
}

run_id="$(date +%s)-$$"
capture_seconds=$((tone_seconds + 4))
remote_capture="/tmp/plank-audio-loop-${run_id}.wav"
recorder_log="/tmp/plank-audio-loop-${run_id}.log"
artifact_dir="${repo_dir}/artifacts/qualification/audio"
artifact="${artifact_dir}/plank-audio-loop-${run_id}.wav"
metrics="${artifact%.wav}.metrics.txt"
mkdir -p "$artifact_dir"

cleanup() {
  ssh "${ssh_options[@]}" "$client" "rm -f -- ${remote_capture}" >/dev/null 2>&1 || true
  rm -f -- "$recorder_log"
}
trap cleanup EXIT

ssh "${ssh_options[@]}" "$client" \
  "timeout ${capture_seconds} pw-record --target ${client_sink_id} --rate 48000 --channels 2 --format s16 ${remote_capture}" \
  >"$recorder_log" 2>&1 &
recorder_pid=$!
sleep 1

ffmpeg -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=${tone_hz}:sample_rate=48000:duration=${tone_seconds}" \
  -filter:a "volume=0.05" -ac 2 -ar 48000 -f pulse "$host_sink"

set +e
wait "$recorder_pid"
recorder_status=$?
set -e
if ((recorder_status != 0 && recorder_status != 124)); then
  echo "client audio recorder failed with status ${recorder_status}" >&2
  exit 1
fi

scp "${ssh_options[@]}" "${client}:${remote_capture}" "$artifact"
[[ -s $artifact ]] || {
  echo "client audio capture is empty" >&2
  exit 1
}

analysis_seconds=$tone_seconds
if ((analysis_seconds > 1)); then
  analysis_seconds=$((analysis_seconds - 1))
fi
band_mean_db() {
  local frequency=$1
  ffmpeg -hide_banner -ss 1.5 -t "$analysis_seconds" -i "$artifact" \
    -af "bandpass=f=${frequency}:width_type=h:w=20,volumedetect" \
    -f null - 2>&1 | awk '/mean_volume:/ { value = $(NF - 1) } END { print value }'
}

target_db=$(band_mean_db "$tone_hz")
control_db=$(band_mean_db "$control_hz")
[[ $target_db =~ ^-?[0-9]+([.][0-9]+)?$ && $control_db =~ ^-?[0-9]+([.][0-9]+)?$ ]] || {
  echo "unable to measure captured frequency bands" >&2
  exit 1
}
delta_db=$(awk -v target="$target_db" -v control="$control_db" 'BEGIN { printf "%.2f", target - control }')
awk -v delta="$delta_db" 'BEGIN { exit !(delta >= 6.0) }' || {
  echo "audio loopback gate failed: target/control delta is ${delta_db} dB" >&2
  exit 1
}

{
  echo "client=${client}"
  echo "client_sink_id=${client_sink_id}"
  echo "host_sink=${host_sink}"
  echo "tone_hz=${tone_hz}"
  echo "control_hz=${control_hz}"
  echo "target_mean_db=${target_db}"
  echo "control_mean_db=${control_db}"
  echo "target_control_delta_db=${delta_db}"
  echo "capture_sha256=$(sha256sum "$artifact" | awk '{print $1}')"
  echo "audio_loopback_gate=pass"
} | tee "$metrics"
