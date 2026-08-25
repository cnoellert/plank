#!/usr/bin/env bash

set -euo pipefail

readonly probe_host="${PLANK_PROBE_HOST:?Set PLANK_PROBE_HOST for the authorized test Host}"
readonly probe_unit="stationconnect-headless-xorg-probe.service"
readonly probe_root="/run/stationconnect/headless-probe"
readonly probe_display=":8"
readonly probe_socket="/tmp/.X11-unix/X8"
readonly xorg_config="${1:-${probe_root}/xorg-dual-virtual.conf}"
readonly expected_monitor_count="${2:-2}"
readonly expected_screen_geometry="${3:-3840x1080}"
readonly nvfbc_probe="${4:-}"
readonly config_delivery="${5:-argument}"

if [[ ${EUID} -ne 0 ]]; then
  echo "run-dual-virtual-probe.sh must run as root" >&2
  exit 1
fi

if [[ $(hostname -s) != "${probe_host}" ]]; then
  echo "refusing to run the disruptive qualification probe outside ${probe_host}" >&2
  exit 1
fi

for required_file in \
  "${xorg_config}" \
  "${probe_root}/virtual-1.edid" \
  "${probe_root}/virtual-2.edid"; do
  if [[ ! -r ${required_file} ]]; then
    echo "missing probe input: ${required_file}" >&2
    exit 1
  fi
done

if systemctl is-active --quiet "${probe_unit}"; then
  echo "probe unit is already active" >&2
  exit 1
fi

xorg_config_arguments=(-config "${xorg_config}")
systemd_environment_arguments=()
case "${config_delivery}" in
  argument)
    ;;
  environment)
    xorg_config_arguments=()
    systemd_environment_arguments=(--setenv="XORGCONFIG=${xorg_config}")
    ;;
  *)
    echo "config delivery must be 'argument' or 'environment'" >&2
    exit 1
    ;;
esac

gdm_was_active=0
if systemctl is-active --quiet gdm.service; then
  gdm_was_active=1
fi

cleanup() {
  set +e
  systemctl stop "${probe_unit}" >/dev/null 2>&1
  if ((gdm_was_active)); then
    systemctl start gdm.service
  fi
}
trap cleanup EXIT INT TERM

if ((gdm_was_active)); then
  systemctl stop gdm.service
fi

systemd-run \
  --unit="${probe_unit%.service}" \
  --collect \
  --property=Type=simple \
  "${systemd_environment_arguments[@]}" \
  /usr/libexec/Xorg "${probe_display}" \
    "${xorg_config_arguments[@]}" \
    -logfile "${probe_root}/Xorg.8.log" \
    -noreset \
    -nolisten tcp \
    -ac

for _ in $(seq 1 20); do
  if [[ -S ${probe_socket} ]]; then
    break
  fi
  if ! systemctl is-active --quiet "${probe_unit}"; then
    break
  fi
  sleep 1
done

if [[ ! -S ${probe_socket} ]]; then
  systemctl status "${probe_unit}" --no-pager || true
  journalctl -u "${probe_unit}" --no-pager -n 120 || true
  if [[ -r ${probe_root}/Xorg.8.log ]]; then
    sed -n '1,260p' "${probe_root}/Xorg.8.log"
  fi
  echo "probe X server did not create ${probe_socket}" >&2
  exit 1
fi

export DISPLAY="${probe_display}"
unset XAUTHORITY

echo "## XRandR providers"
xrandr --listproviders
echo "## XRandR monitors"
xrandr --listmonitors
echo "## XRandR current topology"
xrandr --current
echo "## Xinerama"
xdpyinfo -ext XINERAMA | sed -n '/XINERAMA/,/number of screens/p'
echo "## OpenGL"
glxinfo -B
echo "## NVIDIA metamode"
nvidia-settings -q CurrentMetaMode -t
echo "## NVIDIA GPU"
nvidia-smi --query-gpu=index,name,uuid,driver_version,display_active,memory.used --format=csv,noheader

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

echo "headless Xorg probe: PASS"
