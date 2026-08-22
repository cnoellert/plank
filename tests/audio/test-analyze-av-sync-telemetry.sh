#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work_dir=$(mktemp -d --tmpdir stationconnect-av-sync-test.XXXXXX)
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

stable_log="${work_dir}/stable.log"
drifting_log="${work_dir}/drifting.log"
for index in $(seq 0 60); do
  elapsed=$((index * 1000))
  drifting_audio_media=$((index * 999))
  printf 'StationConnect A/V audio clock: media=%d submit=%d queue=10 device=15 pending=0 frame=5\n' \
    "$elapsed" "$((100000 + elapsed))" >>"$stable_log"
  printf 'StationConnect A/V video clock: media=%d render=%d queue=0 renderer=5\n' \
    "$((500 + elapsed))" "$((200000 + elapsed))" >>"$stable_log"
  printf 'StationConnect A/V audio clock: media=%d submit=%d queue=10 device=15 pending=0 frame=5\n' \
    "$drifting_audio_media" "$((100000 + elapsed))" >>"$drifting_log"
  printf 'StationConnect A/V video clock: media=%d render=%d queue=0 renderer=5\n' \
    "$((500 + elapsed))" "$((200000 + elapsed))" >>"$drifting_log"
done

stable_output=$(
  "$repo_dir/scripts/analyze-av-sync-telemetry.py" "$stable_log" \
    --warmup-seconds 0 \
    --min-duration-seconds 60 \
    --max-relative-drift-ms 1 \
    --max-projected-relative-drift-ms-per-hour 1
)
rg -q '^relative_av_drift_ms=0\.000$' <<<"$stable_output"
rg -q '^audio_clock_rate_error_ms_per_hour=0\.000$' <<<"$stable_output"
rg -q '^video_clock_rate_error_ms_per_hour=0\.000$' <<<"$stable_output"
rg -q '^projected_relative_av_drift_ms_per_hour=0\.000$' <<<"$stable_output"
rg -q '^av_sync_gate=pass$' <<<"$stable_output"

if "$repo_dir/scripts/analyze-av-sync-telemetry.py" "$drifting_log" \
  --warmup-seconds 0 \
  --min-duration-seconds 60 \
  --max-projected-relative-drift-ms-per-hour 100 \
  >"${work_dir}/drifting.out"; then
  echo 'drifting clock unexpectedly passed' >&2
  exit 1
fi
rg -q '^projected_relative_av_drift_ms_per_hour=3600\.000$' \
  "${work_dir}/drifting.out"
rg -q '^audio_clock_rate_error_ms_per_hour=3600\.000$' \
  "${work_dir}/drifting.out"
rg -q '^video_clock_rate_error_ms_per_hour=0\.000$' \
  "${work_dir}/drifting.out"
rg -q '^av_sync_gate=fail \(projected relative drift\)$' \
  "${work_dir}/drifting.out"

echo 'av_sync_analyzer_gate=pass'
