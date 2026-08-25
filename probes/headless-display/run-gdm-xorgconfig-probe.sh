#!/usr/bin/env bash

set -euo pipefail

readonly probe_host="${PLANK_PROBE_HOST:?Set PLANK_PROBE_HOST for the authorized test Host}"
readonly probe_root="/run/stationconnect/headless-probe"
readonly xorg_config="${1:-${probe_root}/xorg-dual-virtual.conf}"
readonly expected_monitor_count="${2:-2}"
readonly expected_screen_geometry="${3:-3840x1080}"
readonly nvfbc_probe="${4:-}"
readonly xorg_config_environment="${5:-${xorg_config}}"
readonly dropin_directory="/run/systemd/system/gdm.service.d"
readonly dropin_path="${dropin_directory}/90-stationconnect-headless-probe.conf"
readonly gdm_xauthority="/run/user/42/gdm/Xauthority"

if [[ ${EUID} -ne 0 ]]; then
  echo "run-gdm-xorgconfig-probe.sh must run as root" >&2
  exit 1
fi
if [[ $(hostname -s) != "${probe_host}" ]]; then
  echo "refusing to run the disruptive GDM probe outside ${probe_host}" >&2
  exit 1
fi
if [[ ! -r ${xorg_config} ]]; then
  echo "missing Xorg probe configuration: ${xorg_config}" >&2
  exit 1
fi
if [[ -e ${dropin_path} ]]; then
  echo "refusing to overwrite existing GDM drop-in: ${dropin_path}" >&2
  exit 1
fi
if ! systemctl is-active --quiet gdm.service; then
  echo "GDM must be active before the integration probe" >&2
  exit 1
fi

cleanup() {
  set +e
  if [[ -e ${dropin_path} ]]; then
    unlink "${dropin_path}"
  fi
  systemctl daemon-reload
  systemctl restart gdm.service
}
trap cleanup EXIT INT TERM

install -d -m 0755 "${dropin_directory}"
printf '%s\n' \
  '[Service]' \
  "Environment=\"XORGCONFIG=${xorg_config_environment}\"" |
  install -m 0644 /dev/stdin "${dropin_path}"
systemctl daemon-reload
systemctl restart gdm.service

for _ in $(seq 1 30); do
  if [[ -S /tmp/.X11-unix/X0 && -r ${gdm_xauthority} ]]; then
    break
  fi
  sleep 1
done

if [[ ! -S /tmp/.X11-unix/X0 || ! -r ${gdm_xauthority} ]]; then
  systemctl status gdm.service --no-pager || true
  journalctl -u gdm.service --no-pager -n 180 || true
  echo "GDM did not restore its X11 display with XORGCONFIG" >&2
  exit 1
fi

export DISPLAY=:0
export XAUTHORITY="${gdm_xauthority}"

echo "## GDM service environment"
systemctl show gdm.service -p Environment
echo "## GDM Xorg process"
pgrep -a -x Xorg
echo "## XRandR monitors"
xrandr --listmonitors
echo "## XRandR current topology"
xrandr --current
echo "## Xinerama"
xdpyinfo -ext XINERAMA | sed -n '/XINERAMA/,/number of screens/p'
echo "## OpenGL"
glxinfo -B

if [[ -n ${nvfbc_probe} ]]; then
  if [[ ! -x ${nvfbc_probe} ]]; then
    echo "NvFBC probe is not executable: ${nvfbc_probe}" >&2
    exit 1
  fi
  echo "## NvFBC CUDA capture"
  "${nvfbc_probe}" --frames 120 --fps 60
fi

monitor_count=$(xrandr --listmonitors | awk 'NR == 1 {print $2}')
screen_geometry=$(xrandr --current | awk 'NR == 1 {print $8 "x" $10}' | tr -d ',')
if [[ ${monitor_count} != "${expected_monitor_count}" ]]; then
  echo "expected ${expected_monitor_count} RandR monitors, found ${monitor_count}" >&2
  exit 1
fi
if [[ ${screen_geometry} != "${expected_screen_geometry}" ]]; then
  echo "expected ${expected_screen_geometry} screen, found ${screen_geometry}" >&2
  exit 1
fi

echo "GDM XORGCONFIG headless probe: PASS"
