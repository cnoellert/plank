#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}

sudo -n "${build_dir}/plank-probe-wacom"

descriptor_count=0
for hidraw_path in /sys/class/hidraw/hidraw*; do
  uevent=${hidraw_path}/device/uevent
  [[ -r ${uevent} ]] || continue
  if ! grep -q '^HID_ID=0003:0000056A:' "${uevent}"; then
    continue
  fi
  descriptor=${hidraw_path}/device/report_descriptor
  echo "  hidraw=/dev/${hidraw_path##*/}"
  grep -E '^(HID_ID|HID_NAME|HID_UNIQ)=' "${uevent}" | sed 's/^/    /'
  echo "    descriptor_bytes=$(sudo -n wc -c "${descriptor}" | awk '{print $1}')"
  echo "    descriptor_sha256=$(sudo -n sha256sum "${descriptor}" | awk '{print $1}')"
  descriptor_count=$((descriptor_count + 1))
done

echo "wacom_hid_descriptors=${descriptor_count}"
((descriptor_count > 0))
