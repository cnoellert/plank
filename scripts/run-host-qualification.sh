#!/usr/bin/env bash

set -uo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work_root=${PLANK_WORK_ROOT:-"${XDG_CACHE_HOME:-${HOME}/.cache}/plank-build/work"}
build_dir=${PLANK_BUILD_DIR:-"${work_root}/qualification"}
report_file=${1:-"${repo_dir}/artifacts/qualification/reports/qualification-report.md"}
kms_device=${PLANK_DRM_DEVICE:-/dev/dri/card0}

active_session=$(loginctl show-seat seat0 --property=ActiveSession --value 2>/dev/null || true)
detected_x11_user=
if [[ -n "${active_session}" ]]; then
  detected_x11_user=$(loginctl show-session "${active_session}" --property=Name --value 2>/dev/null || true)
fi
x11_user=${PLANK_X11_USER:-${detected_x11_user:-gdm}}
x11_uid=$(id -u "${x11_user}")
detected_x11_display=$(who | awk -v user="${x11_user}" '$1 == user && $2 ~ /^:[0-9]+$/ { print $2; exit }')
x11_display=${PLANK_X11_DISPLAY:-${detected_x11_display:-:0}}
x11_authority=${PLANK_X11_AUTHORITY:-/run/user/${x11_uid}/gdm/Xauthority}

mkdir -p -- "${build_dir}" "$(dirname -- "${report_file}")"

cmake -S "${repo_dir}" -B "${build_dir}" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "${build_dir}" --parallel
ctest --test-dir "${build_dir}" --output-on-failure

overall_result=0
{
  echo '# PLANK Host Qualification Report'
  echo
  echo "Generated: $(date --iso-8601=seconds)"
  echo
  echo '## Host'
  echo
  echo '```text'
  uname -a
  sed -n '1,8p' /etc/os-release
  nvidia-smi --query-gpu=name,driver_version,display_active --format=csv,noheader 2>&1 || overall_result=1
  echo '```'
  echo
  echo '## Active Xorg Source'
  echo
  echo '```text'
  if ! sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
      XAUTHORITY="${x11_authority}" xdpyinfo 2>&1 |
      sed -n '/dimensions:/p;/depths (/p;/depth of root window:/p'; then
    overall_result=1
  fi
  sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
    XAUTHORITY="${x11_authority}" xrandr --current 2>&1 |
    sed -n '1p;/ connected /p' || overall_result=1
  echo '```'
  echo
  echo '## DRM/KMS Inventory'
  echo
  echo '```text'
  stat -c '%A %U %G %n' "${kms_device}" 2>&1 || overall_result=1
  modeset_path=/sys/module/nvidia_drm/parameters/modeset
  if [[ -r "${modeset_path}" ]]; then
    modeset=$(<"${modeset_path}")
  else
    modeset=$(sudo -n cat "${modeset_path}" 2>&1) || overall_result=1
  fi
  echo "nvidia_drm_modeset=${modeset}"
  if [[ "${modeset}" != Y ]]; then
    echo 'prerequisite=fail (enable nvidia_drm.modeset=1 and reboot)'
    overall_result=1
  fi
  if ! "${build_dir}/plank-probe-kms" "${kms_device}" --inventory-only 2>&1; then
    echo 'retrying KMS inventory with non-interactive sudo'
    sudo -n "${build_dir}/plank-probe-kms" "${kms_device}" --inventory-only 2>&1 || overall_result=1
  fi
  echo '```'
  echo
  echo '## NVIDIA X11 Framebuffer Capture'
  echo
  echo '```text'
  if [[ ! -x "${build_dir}/plank-probe-nvfbc" ]]; then
    echo 'nvfbc_probe=unavailable (set NVFBC_SDK_ROOT to NVIDIA Capture SDK 9.0)'
    overall_result=1
  elif env DISPLAY="${x11_display}" XAUTHORITY=/dev/null \
      "${build_dir}/plank-probe-nvfbc" --frames 600 --fps 60 2>&1; then
    echo 'nvfbc_operational_gate=pass'
  elif sudo -n -u "${x11_user}" env DISPLAY="${x11_display}" \
      XAUTHORITY="${x11_authority}" \
      "${build_dir}/plank-probe-nvfbc" --frames 600 --fps 60 2>&1; then
    echo 'nvfbc_operational_gate=pass'
  else
    echo 'nvfbc_operational_gate=fail'
    overall_result=1
  fi
  echo 'native_10_bit_capture_gate=unsupported (non-blocking for the 8-bit-source production baseline)'
  echo '```'
  echo
  echo '## NVENC HEVC FRExt 10-bit 4:4:4'
  echo
  echo '```text'
  "${build_dir}/plank-probe-nvenc" 2>&1 || overall_result=1
  "${repo_dir}/scripts/probe-nvenc-hevc44410.sh" 2>&1 || overall_result=1
  echo '```'
  echo
  echo '## Wacom Host Inventory'
  echo
  echo '```text'
  "${repo_dir}/scripts/probe-wacom-host.sh" 2>&1 || overall_result=1
  echo '```'
  echo
  echo '## PAM/SSSD Account Policy'
  echo
  echo 'This check does not perform password authentication.'
  echo
  echo '```text'
  "${repo_dir}/scripts/probe-pam-policy.sh" 2>&1 || overall_result=1
  echo '```'
  echo
  echo '## Result'
  echo
  if ((overall_result == 0)); then
    echo 'Initial host inventory: PASS'
  else
    echo 'Initial host inventory: INCOMPLETE (inspect failures above)'
  fi
} >"${report_file}"

echo "Wrote ${report_file}"
exit "${overall_result}"
