#!/usr/bin/env bash

set -euo pipefail

if [[ ${1:-} != --confirm-display-outage ]]; then
  echo "usage: $0 --confirm-display-outage [--accel=glamor|--accel=none]" >&2
  echo 'This probe temporarily stops the display manager.' >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}
case ${2:---accel=glamor} in
  --accel=glamor)
    config=${repo_dir}/probes/kms/xorg-modesetting-depth30.conf
    ;;
  --accel=none)
    config=${repo_dir}/probes/kms/xorg-modesetting-depth30-shadow.conf
    ;;
  *)
    echo "unsupported acceleration selection: ${2}" >&2
    exit 2
    ;;
esac
unit=plank-xorg-kms-test.service
display=:1
display_manager_was_active=no

restore_display_manager() {
  local result=$?
  trap - EXIT
  sudo -n systemctl stop "${unit}" >/dev/null 2>&1 || true
  if [[ ${display_manager_was_active} == yes ]]; then
    sudo -n systemctl start display-manager.service || true
  fi
  exit "${result}"
}
trap restore_display_manager EXIT

cmake --build "${build_dir}" --parallel
if systemctl is-active --quiet display-manager.service; then
  display_manager_was_active=yes
fi

echo 'Stopping the display manager for the isolated KMS test.'
sudo -n systemctl stop display-manager.service
sudo -n systemctl reset-failed "${unit}" >/dev/null 2>&1 || true

sudo -n systemd-run --quiet --unit="${unit%.service}" \
  --property=Type=simple \
  /usr/libexec/Xorg "${display}" -config "${config}" -noreset -nolisten tcp -ac vt1

xorg_ready=no
for _ in {1..20}; do
  if systemctl is-active --quiet "${unit}" &&
      DISPLAY="${display}" xdpyinfo >/dev/null 2>&1; then
    xorg_ready=yes
    break
  fi
  sleep 0.5
done

if [[ ${xorg_ready} != yes ]]; then
  echo 'Generic modesetting Xorg failed to become ready.' >&2
  sudo -n journalctl -u "${unit}" --no-pager -n 120 >&2
  exit 3
fi

echo '## Generic modesetting Xorg'
DISPLAY="${display}" xdpyinfo |
  sed -n '/dimensions:/p;/depths (/p;/depth of root window:/p'
DISPLAY="${display}" xrandr --current | sed -n '1p;/ connected /p'
DISPLAY="${display}" glxinfo -B |
  sed -n '/direct rendering:/p;/OpenGL vendor string:/p;/OpenGL renderer string:/p'

echo '## DRM scanout'
sudo -n "${build_dir}/plank-probe-kms" /dev/dri/card0
