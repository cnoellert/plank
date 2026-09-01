#!/usr/bin/env bash

set -euo pipefail

if [[ ${1:-} != --confirm-display-outage ]]; then
  echo "usage: $0 --confirm-display-outage" >&2
  echo 'This probe temporarily stops the display manager.' >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}
display_manager_was_active=no

restore_display_manager() {
  local result=$?
  trap - EXIT
  if [[ ${display_manager_was_active} == yes ]]; then
    sudo -n systemctl start display-manager.service || true
  fi
  exit "${result}"
}
trap restore_display_manager EXIT

cmake -S "${repo_dir}" -B "${build_dir}" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "${build_dir}" --parallel

if systemctl is-active --quiet display-manager.service; then
  display_manager_was_active=yes
fi
echo 'Stopping the display manager for the direct XB30 KMS test.'
sudo -n systemctl stop display-manager.service
sudo -n "${build_dir}/plank-probe-kms-xb30" /dev/dri/card0
