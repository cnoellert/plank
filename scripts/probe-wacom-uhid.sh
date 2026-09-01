#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${PLANK_BUILD_DIR:-"${repo_dir}/build/qualification"}
descriptor=${PLANK_WACOM_DESCRIPTOR:-/sys/class/hidraw/hidraw2/device/report_descriptor}
output=$(mktemp --tmpdir plank-wacom-uhid.XXXXXX.log)
probe_pid=

cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n ${probe_pid} ]]; then
    sudo -n kill "${probe_pid}" >/dev/null 2>&1 || true
    wait "${probe_pid}" >/dev/null 2>&1 || true
  fi
  rm -f -- "${output}"
  exit "${result}"
}
trap cleanup EXIT

sudo -n modprobe uhid
if [[ ! -d /sys/module/uhid ]]; then
  echo 'UHID kernel module failed to load.' >&2
  exit 3
fi

sudo -n "${build_dir}/plank-probe-uhid" "${descriptor}" >"${output}" 2>&1 &
probe_pid=$!
sleep 2
udevadm settle

virtual_device_count=$(sudo -n "${build_dir}/plank-probe-wacom" |
  grep -c 'PLANK Virtual Intuos Pro L' || true)
echo "virtual_wacom_event_devices=${virtual_device_count}"

set +e
wait "${probe_pid}"
probe_status=$?
set -e
probe_pid=
cat "${output}"
if ((probe_status != 0)); then
  exit "${probe_status}"
fi
((virtual_device_count > 0))
