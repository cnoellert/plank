#!/usr/bin/env bash

set -euo pipefail

if (($# < 1 || $# > 4)); then
  echo "usage: $0 BITSTREAM [FRAME_COUNT] [SUBMIT_LEAD_US] [DRM_DEVICE]" >&2
  exit 2
fi
if [[ ${CONNECT_ALLOW_DISPLAY_STOP:-no} != yes ]]; then
  echo "set CONNECT_ALLOW_DISPLAY_STOP=yes to authorize the isolated KMS run" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=${CONNECT_CLIENT_BUILD_DIR:-"${repo_dir}/build/client-qualification"}
CONNECT_BUILD_ONLY=1 "${repo_dir}/scripts/probe-intel-client-kms.sh" "$@"

was_active=no
if systemctl is-active --quiet display-manager; then
  was_active=yes
fi
restore_display_manager() {
  if [[ ${was_active} == yes ]]; then
    sudo systemctl start display-manager
  fi
}
trap restore_display_manager EXIT INT TERM

sudo -v
if [[ ${was_active} == yes ]]; then
  sudo systemctl stop display-manager
fi
set +e
sudo env LIBVA_DRIVER_NAME=iHD \
  "${build_dir}/connect-probe-client-kms" "$@"
status=$?
set -e
restore_display_manager
trap - EXIT INT TERM
exit "${status}"
