#!/usr/bin/env bash

set -euo pipefail

if (($# < 2 || $# > 3)); then
  echo "usage: $0 MOONLIGHT_SOURCE_DIR FFMPEG_WORK_DIR [BUILD_DIR]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=$(realpath -- "$1")
ffmpeg_work_dir=$(realpath -- "$2")
build_dir=$(realpath -m -- "${3:-${repo_dir}/build/package-client}")
ffmpeg_prefix="${ffmpeg_work_dir}/install"

for command_name in find git make mktemp pkg-config qmake6 readelf realpath rg stat timeout; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

package_version=$(<"${repo_dir}/packaging/VERSION")
[[ $package_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]] || {
  echo "invalid shared package version: ${package_version}" >&2
  exit 1
}

[[ -f ${source_dir}/moonlight-qt.pro ]] || {
  echo "Moonlight source tree is unavailable: ${source_dir}" >&2
  exit 1
}
if [[ -n $(git -C "$source_dir" status --porcelain) ]]; then
  echo "Moonlight source tree is dirty; refusing a package build" >&2
  exit 1
fi
submodule_status=$(git -C "$source_dir" submodule status --recursive)
if rg -q '^[+-U]' <<<"$submodule_status"; then
  echo "Moonlight recursive submodules are missing or not at their pinned commits:" >&2
  printf '%s\n' "$submodule_status" >&2
  exit 1
fi
if [[ -d ${build_dir} && -n $(find "$build_dir" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
  echo "package build directory is not empty: ${build_dir}" >&2
  exit 1
fi

# StationConnect is a remote-workstation client. Controller input and
# controller-driven UI navigation are deliberately outside the product scope.
for removed_path in \
  app/SDL_GameControllerDB \
  app/gui/GamepadMapper.qml \
  app/gui/sdlgamepadkeynavigation.cpp \
  app/gui/sdlgamepadkeynavigation.h \
  app/settings/mappingfetcher.cpp \
  app/settings/mappingfetcher.h \
  app/settings/mappingmanager.cpp \
  app/settings/mappingmanager.h \
  app/streaming/input/gamepad.cpp; do
  [[ ! -e ${source_dir}/${removed_path} ]] || {
    echo "gamepad support is present in StationConnect client source: ${removed_path}" >&2
    exit 1
  }
done
if rg -n \
  'SdlGamepadKeyNavigation|SDL_INIT_(JOYSTICK|GAMECONTROLLER)|Gamepad Settings|multi-controller|background-gamepad|swap-gamepad-buttons' \
  "$source_dir/app" \
  --glob '!**/languages/**' \
  --glob '!**/Info.plist'; then
  echo "gamepad support or controller UI navigation is present in StationConnect client source" >&2
  exit 1
fi
echo "client_gamepad_absence_gate=pass"

# StationConnect uses per-session operating-system authentication. It has no
# GameStream PIN workflow or persistent client-certificate identity.
for removed_path in \
  app/backend/identitymanager.cpp \
  app/backend/identitymanager.h \
  app/backend/nvpairingmanager.cpp \
  app/backend/nvpairingmanager.h \
  app/cli/pair.cpp \
  app/cli/pair.h \
  app/gui/CliPair.qml; do
  [[ ! -e ${source_dir}/${removed_path} ]] || {
    echo "legacy pairing source is present in StationConnect client: ${removed_path}" >&2
    exit 1
  }
done
if rg -n \
  'IdentityManager|NvPairingManager|PendingPairingTask|PairRequested|pairComputer|generatePinString|setServerCert|serverCert' \
  "$source_dir/app" \
  --glob '!**/languages/**' \
  --glob '!**/deploy/**'; then
  echo "legacy PIN or persistent client-certificate workflow is present in StationConnect client" >&2
  exit 1
fi
echo "client_pairing_absence_gate=pass"

# StationConnect disconnects streams without changing the physical workstation
# display or terminating the workstation application. Keep Moonlight's legacy
# SOPS and remote app-cancel controls out of the product.
for removed_path in \
  app/cli/quitstream.cpp \
  app/cli/quitstream.h \
  app/gui/CliQuitStreamSegue.qml \
  app/gui/QuitSegue.qml \
  app/streaming/input/abstouch.cpp \
  app/streaming/input/reltouch.cpp; do
  [[ ! -e ${source_dir}/${removed_path} ]] || {
    echo "remote host-control source is present: ${removed_path}" >&2
    exit 1
  }
done
if rg -n \
  'Host Settings|gameOptimizations|quitAppAfter|quitRunningApp|quitAppCompleted|unlockBitrate|Unlock bitrate limit|absoluteTouchMode|swapMouseButtons|reverseScrollDirection|absoluteMouseMode|touchscreen-trackpad|mouse-buttons-swap|reverse-scroll-direction|absolute-mouse|Use touchscreen as a virtual trackpad|Swap left and right mouse buttons|Reverse mouse scrolling direction|Optimize mouse for remote desktop|KeyComboToggleMouseMode|SDL_FINGER(DOWN|MOTION|UP)|LiSendTouchEvent|SDL_(Get|Set)RelativeMouseMode|[?&]sops=|game-optimization|quit-after' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "legacy SOPS or remote app termination is present in StationConnect client" >&2
  exit 1
fi
echo "client_remote_host_control_absence_gate=pass"

# Focus loss must stop local raw-Wacom forwarding without sending the
# destructive detach that removes and recreates host UHID/XInput endpoints.
client_common_dir="${source_dir}/moonlight-common-c/moonlight-common-c/src"
for required_raw_hid_token in \
  '#define SC_RAW_HID_WIRE_VERSION 2U' \
  'SC_RAW_HID_SUSPEND = 13'; do
  rg -Fq "$required_raw_hid_token" "$client_common_dir" || {
    echo "client raw-HID focus-suspend protocol invariant is missing: ${required_raw_hid_token}" >&2
    exit 1
  }
done
rg -q '#define[[:space:]]+LI_FF_RAW_HID_FOCUS_SUSPEND[[:space:]]+0x20' \
  "$client_common_dir/Limelight.h" || {
  echo "client raw-HID focus-suspend feature bit is missing" >&2
  exit 1
}
for required_raw_hid_token in \
  LI_FF_RAW_HID_FOCUS_SUSPEND \
  suspendForFocusLoss \
  'sendFrame(SC_RAW_HID_SUSPEND, 0, 0, nullptr, 0)'; do
  rg -Fq "$required_raw_hid_token" \
    "$source_dir/app/streaming/input/input.cpp" \
    "$source_dir/app/streaming/input/linuxrawwacom.cpp" \
    "$source_dir/app/streaming/input/linuxrawwacom.h" || {
    echo "client raw-HID focus-suspend invariant is missing: ${required_raw_hid_token}" >&2
    exit 1
  }
done
rg -U -q 'void LinuxRawWacomInput::setActive\(bool active\)(.|\n)*?if \(!active\) \{(.|\n)*?suspendForFocusLoss\(\);' \
  "$source_dir/app/streaming/input/linuxrawwacom.cpp" || {
  echo "client focus loss does not use non-destructive raw-HID suspension" >&2
  exit 1
}
echo "client_raw_hid_focus_suspend_gate=pass"

# High-bitrate video recovery uses upstream nanors with runtime-selected SIMD
# and GFNI implementations. Keep the old scalar Reed-Solomon source out of the
# client build while preserving StationConnect's extended-FEC queue logic.
client_common_root="${source_dir}/moonlight-common-c/moonlight-common-c"
for required_fec_source in \
  nanors/rs.c \
  nanors/deps/obl/oblas_common.c \
  nanors/deps/obl/oblas_lite.c; do
  [[ -f "${client_common_root}/${required_fec_source}" ]] || {
    echo "optimized FEC source is unavailable: ${required_fec_source}" >&2
    exit 1
  }
  rg -Fq "\$\$COMMON_C_DIR/${required_fec_source}" \
    "${source_dir}/moonlight-common-c/moonlight-common-c.pro" || {
    echo "optimized FEC source is absent from the Qt build: ${required_fec_source}" >&2
    exit 1
  }
done
for required_fec_token in \
  'reed_solomon_decode(' \
  'memcpy(queue->rs->p, parity, sizeof(parity));'; do
  rg -Fq "$required_fec_token" "$client_common_root/src" || {
    echo "nanors FEC integration invariant is missing: ${required_fec_token}" >&2
    exit 1
  }
done
if rg -n 'RS_DIR|reedsolomon/rs\.c|reed_solomon_reconstruct\(' \
  "${source_dir}/moonlight-common-c/moonlight-common-c.pro" \
  "$client_common_root/src"; then
  echo "legacy scalar Reed-Solomon integration is present" >&2
  exit 1
fi
echo "client_simd_fec_gate=pass"

# Remote-workstation sessions capture OS-level key combinations by default so
# shortcuts such as Alt+Tab reach the host in both windowed and borderless mode.
rg -U -q 'settings\.value\(SER_CAPTURESYSKEYS,\n[[:space:]]+static_cast<int>\(CaptureSysKeysMode::CSK_ALWAYS\)\)' \
  "$source_dir/app/settings/streamingpreferences.cpp" || {
  echo "system keyboard shortcut capture does not default to Always" >&2
  exit 1
}
echo "client_system_shortcut_default_gate=pass"

# StationConnect has one qualified SDR H.264 High 10 4:4:4 identity profile,
# decoded through the proven FFmpeg software path, and one windowed launcher
# mode. These are product invariants, not user preferences or CLI overrides.
if rg -n \
  'enableHdr|enableYUV444|supportsHdr|Enable HDR|Enable YUV 4:4:4|addToggleOption\("(hdr|yuv444)"|GUI display mode|uiDisplayMode|UIDisplayMode|UI_(WINDOWED|MAXIMIZED|FULLSCREEN)|uidisplaymode|startwindowed' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "optional HDR, YUV 4:4:4, or GUI display-mode controls are present in StationConnect client" >&2
  exit 1
fi
if ! rg -U -q 'id: codecComboBox\n[[:space:]]+enabled: false' \
  "$source_dir/app/gui/SettingsView.qml" ||
   rg -q 'VCC_(AUTO|FORCE_HEVC|FORCE_AV1)' \
  "$source_dir/app/gui/SettingsView.qml"; then
  echo "the StationConnect video codec selector is not locked to H.264" >&2
  exit 1
fi
if rg -n \
  'm_SupportedVideoFormats\.append\(VIDEO_FORMAT_(H264\)|H265\)|H265_MAIN|AV1_MAIN)' \
  "$source_dir/app/streaming/session.cpp"; then
  echo "a 4:2:0 video profile is advertised by the StationConnect session" >&2
  exit 1
fi
profile_appends=$(rg -F \
  'm_SupportedVideoFormats.append(VIDEO_FORMAT_' \
  "$source_dir/app/streaming/session.cpp" || true)
if [[ $profile_appends != *'m_SupportedVideoFormats.append(VIDEO_FORMAT_H264_HIGH10_444);'* ]] ||
   [[ $(wc -l <<<"$profile_appends") -ne 1 ]]; then
  echo "StationConnect must advertise only H.264 High 10 4:4:4" >&2
  printf '%s\n' "$profile_appends" >&2
  exit 1
fi
if ! rg -Fq \
  'm_Preferences->videoDecoderSelection = StreamingPreferences::VDS_FORCE_SOFTWARE;' \
  "$source_dir/app/streaming/session.cpp" ||
   rg -Fq \
  'm_Preferences->videoDecoderSelection = StreamingPreferences::VDS_AUTO;' \
  "$source_dir/app/streaming/session.cpp"; then
  echo "StationConnect must use the qualified FFmpeg software decoder" >&2
  exit 1
fi
echo "client_sdr_444_profile_gate=pass"

# The StationConnect client is Wayland-only. It offers compositor-managed
# borderless and decorated/resizable windowed streaming, but no exclusive
# modesetting path.
if rg -n '\bWM_FULLSCREEN\b|\{"fullscreen",[[:space:]]*StreamingPreferences::WM|m_FullScreenFlag[[:space:]]*=[[:space:]]*SDL_WINDOW_FULLSCREEN;' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "exclusive fullscreen support is present in the Wayland-only StationConnect client" >&2
  exit 1
fi
for required_window_token in \
  SDL_HINT_VIDEO_WAYLAND_ALLOW_LIBDECOR \
  SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR \
  SDL_HINT_OVERRIDE \
  SDL_RestoreWindow \
  SDL_SetWindowBordered \
  SDL_SetWindowResizable \
  'Action::ToggleFullscreen' \
  fullscreenContains \
  'toolbar fullscreen toggle requested'; do
  rg -q "$required_window_token" "$source_dir/app" || {
    echo "decorated Wayland window invariant is missing: ${required_window_token}" >&2
    exit 1
  }
done
echo "client_wayland_window_mode_gate=pass"

# Manually entered workstations are persistent bookmarks even while offline.
# They retain both the entered address and editable nickname, then bind to the
# first server identity that successfully answers at that address.
for required_bookmark_token in \
  stationconnect-manual-bookmark \
  stationconnect-server-uuid \
  acceptsServerUuid \
  'Address or hostname' \
  Nickname; do
  rg -Fq "$required_bookmark_token" "$source_dir/app" || {
    echo "offline workstation bookmark invariant is missing: ${required_bookmark_token}" >&2
    exit 1
  }
done
rg -U -q 'addNewHostManually\(addressText\.text\.trim\(\),[[:space:]]*nicknameText\.text\.trim\(\),[[:space:]]*addDisplayChoice\.currentIndex === 0\)' \
  "$source_dir/app/gui/main.qml" || {
  echo "manual workstation dialog does not submit address, nickname, and display preference" >&2
  exit 1
}
for required_bookmark_editor_token in \
  'Edit bookmark…' \
  editComputerBookmark \
  editManualBookmark \
  editDisplayChoice; do
  rg -Fq "$required_bookmark_editor_token" "$source_dir/app" || {
    echo "workstation bookmark editor invariant is missing: ${required_bookmark_editor_token}" >&2
    exit 1
  }
done
if rg -Fq 'text: qsTr("Display…")' "$source_dir/app/gui/PcView.qml"; then
  echo "standalone workstation display menu must remain inside bookmark editing" >&2
  exit 1
fi
rg -U -q 'id: addPcDialog(.|\n)*width: Math\.min\(640, parent\.width - 40\)(.|\n)*dim: false' \
  "$source_dir/app/gui/main.qml" || {
  echo "connection dialog must remain wide without dimming the launcher" >&2
  exit 1
}
rg -U -q 'id: addPcDialog(.|\n)*ColumnLayout \{\n[[:space:]]+width: parent\.width' \
  "$source_dir/app/gui/main.qml" || {
  echo "connection fields must fill the dialog width" >&2
  exit 1
}
if rg -q 'placeholderText: qsTr\("hardware-test-host(\.stationconnect\.io)?"\)' \
  "$source_dir/app/gui/main.qml"; then
  echo "connection dialog contains misleading workstation example text" >&2
  exit 1
fi
rg -U -q 'case AddressRole:(.|\n)*!computer->manualAddress\.isNull\(\)(.|\n)*!computer->activeAddress\.isNull\(\)(.|\n)*return QString\(\);' \
  "$source_dir/app/gui/computermodel.cpp" || {
  echo "workstation rows can expose a null manual address" >&2
  exit 1
}
echo "client_offline_bookmark_gate=pass"

# Workstation diagnostics belong in the bounded persistent log rather than a
# user-facing context-menu dump of internal addresses and identifiers.
if rg -n 'DetailsRole|showPcDetailsDialog|View Details|Running Game ID|MAC Address:' \
  "$source_dir/app/gui" \
  --glob '!**/languages/**'; then
  echo "legacy workstation details UI is present" >&2
  exit 1
fi
echo "client_workstation_details_absence_gate=pass"

# StationConnect workstations are expected to be available through their
# approved network path. Do not retain Moonlight's Wake-on-LAN UI, MAC-address
# persistence, CLI auto-wake, or magic-packet transport.
if rg -n 'Wake PC|WakeableRole|wakeComputer|macAddress|SER_MAC|wolPayload|STATIC_WOL_PORTS|DYNAMIC_WOL_PORTS|computer->wake\(\)' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "Wake-on-LAN support is present in StationConnect client" >&2
  exit 1
fi
echo "client_wake_on_lan_absence_gate=pass"

# A configured physical path MTU is converted once to a conservative,
# 16-byte-aligned video packet size. Keep the old raw packet-size control out.
if rg -n 'packet-size|SER_PACKETSIZE|\bpacketSize MEMBER' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "legacy raw packet-size configuration is present in StationConnect client" >&2
  exit 1
fi
for required_mtu_token in \
  'Network Settings' \
  stationconnect-network-mtu \
  videoPacketSizeForPhysicalMtu; do
  rg -Fq "$required_mtu_token" "$source_dir/app" || {
    echo "client MTU configuration invariant is missing: ${required_mtu_token}" >&2
    exit 1
  }
done
rg -U -q 'id: networkSettingsGroupBox\n[[:space:]]+parent: settingsColumn1' \
  "$source_dir/app/gui/SettingsView.qml" || {
  echo "Network Settings is not assigned to the left configuration column" >&2
  exit 1
}
echo "client_network_mtu_gate=pass"

# mDNS discovery is opt-in. A deployment env override takes precedence over
# the user preference and locks the corresponding UI control.
rg -Fq 'settings.value(SER_MDNS, false)' \
  "$source_dir/app/settings/streamingpreferences.cpp" || {
  echo "client mDNS discovery does not default to disabled" >&2
  exit 1
}
for required_mdns_token in \
  STATIONCONNECT_MDNS_DISCOVERY \
  mdnsDiscoveryManaged \
  '!StreamingPreferences.mdnsDiscoveryManaged'; do
  rg -Fq "$required_mdns_token" "$source_dir/app" || {
    echo "client managed mDNS invariant is missing: ${required_mdns_token}" >&2
    exit 1
  }
done
rg -Fq 'source "${client_env}"' "$repo_dir/packaging/bin/stationconnect-client" || {
  echo "client launcher does not load its deployment env file" >&2
  exit 1
}
rg -Fq 'STATIONCONNECT_MDNS_DISCOVERY=${STATIONCONNECT_MDNS_DISCOVERY:-0}' \
  "$repo_dir/packaging/bin/stationconnect-client" || {
  echo "client launcher does not default mDNS discovery to disabled" >&2
  exit 1
}
rg -Fxq 'STATIONCONNECT_MDNS_DISCOVERY=0' \
  "$repo_dir/packaging/systemd/client.env.example" || {
  echo "client mDNS example does not default to disabled" >&2
  exit 1
}
echo "client_mdns_default_off_gate=pass"

# Linux client diagnostics must survive a reboot and remain readable without
# root access. Keep the same redacted output in both the user journal and a
# private XDG state log, with bounded file size and retention.
for required_log_token in \
  XDG_STATE_HOME \
  '.local/state' \
  'stationconnect/logs'; do
  rg -Fq "$required_log_token" "$source_dir/app/path.cpp" || {
    echo "client persistent log path invariant is missing: ${required_log_token}" >&2
    exit 1
  }
done
for required_log_token in \
  'stationconnect-client-*.log' \
  'MAX_LOG_SIZE_BYTES (10 * 1024 * 1024)' \
  'QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner' \
  'QFileDevice::ReadOwner | QFileDevice::WriteOwner' \
  's_LoggerFileStream << message' \
  '#if defined(Q_OS_LINUX) || !defined(LOG_TO_FILE)' \
  'Persistent client log:'; do
  rg -Fq "$required_log_token" "$source_dir/app/main.cpp" || {
    echo "client persistent log invariant is missing: ${required_log_token}" >&2
    exit 1
  }
done
echo "client_persistent_log_source_gate=pass"

export PKG_CONFIG_PATH="${ffmpeg_prefix}/lib/pkgconfig"
export LD_LIBRARY_PATH="${ffmpeg_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ $(pkg-config --modversion libavcodec) == 63.* ]] || {
  echo "FFmpeg 9 libavcodec pkg-config metadata was not selected" >&2
  exit 1
}

mkdir -p "$build_dir"
(
  cd "$build_dir"
  qmake6 "$source_dir" CONFIG+=release \
    "STATIONCONNECT_VERSION=${package_version}" \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${source_dir}=../src" \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${source_dir}=../src"
  make -j"$(nproc)"
)

client_binary="${build_dir}/app/moonlight"
[[ -x ${client_binary} ]] || {
  echo "Moonlight package binary was not produced" >&2
  exit 1
}
rg -a -Fq "$package_version" "$client_binary" || {
  echo "Moonlight does not embed the StationConnect package version: ${package_version}" >&2
  exit 1
}
echo "stationconnect_client_version=${package_version}"
echo "client_version_banner_gate=pass"
dynamic_section=$(readelf -d "$client_binary")
for soname in libavcodec.so.63 libavutil.so.61 libswscale.so.10 libswresample.so.7; do
  rg -q "Shared library: \[${soname//./\\.}\]" <<<"$dynamic_section" || {
    echo "Moonlight did not link the required FFmpeg 9 SONAME: ${soname}" >&2
    exit 1
  }
done
"${repo_dir}/scripts/audit-package-runtime.sh" \
  "$client_binary" "${ffmpeg_prefix}/lib"

log_runtime_root=$(mktemp -d)
log_runtime_home="${log_runtime_root}/home"
log_runtime_state="${log_runtime_root}/state"
log_runtime_dir="${log_runtime_state}/stationconnect/logs"
log_runtime_config="${log_runtime_root}/config"
log_runtime_cache="${log_runtime_root}/cache"
log_runtime_session="${log_runtime_root}/runtime"
mkdir -p "$log_runtime_home" "$log_runtime_dir" "$log_runtime_config" \
  "$log_runtime_cache" "$log_runtime_session"
chmod 0700 "$log_runtime_home" "$log_runtime_dir" "$log_runtime_config" \
  "$log_runtime_cache" "$log_runtime_session"
for old_log in {01..11}; do
  touch "${log_runtime_dir}/stationconnect-client-20000101-000000-000-${old_log}.log"
done
chmod 0600 "${log_runtime_dir}"/*.log

set +e
log_runtime_output=$(env \
  HOME="$log_runtime_home" \
  QT_QPA_PLATFORM=offscreen \
  XDG_CACHE_HOME="$log_runtime_cache" \
  XDG_CONFIG_HOME="$log_runtime_config" \
  XDG_RUNTIME_DIR="$log_runtime_session" \
  XDG_STATE_HOME="$log_runtime_state" \
  timeout 10s "$client_binary" --version 2>&1)
log_runtime_status=$?
set -e
if [[ $log_runtime_status -ne 0 ]]; then
  printf '%s\n' "$log_runtime_output" >&2
  echo "client persistent log runtime exited with status ${log_runtime_status}" >&2
  exit 1
fi

mapfile -t runtime_logs < <(find "$log_runtime_dir" -maxdepth 1 -type f \
  -name 'stationconnect-client-*.log' -print)
if [[ ${#runtime_logs[@]} -ne 10 ]]; then
  printf '%s\n' "$log_runtime_output" >&2
  echo "client did not retain exactly 10 persistent logs" >&2
  exit 1
fi
runtime_log=$(find "$log_runtime_dir" -maxdepth 1 -type f -size +0c -print -quit)
if [[ -z $runtime_log ]] ||
   [[ $(stat -c '%a' "$log_runtime_dir") != 700 ]] ||
   [[ $(stat -c '%a' "$runtime_log") != 600 ]] ||
   ! rg -Fq 'Persistent client log:' "$runtime_log" ||
   ! rg -Fq 'Persistent client log:' <<<"$log_runtime_output"; then
  printf '%s\n' "$log_runtime_output" >&2
  echo "client persistent log path, permissions, content, or stderr mirror is invalid" >&2
  exit 1
fi
rm -rf -- "$log_runtime_root"
echo "client_persistent_log_runtime_gate=pass"

echo "client_binary=${client_binary}"
echo "client_package_binary_gate=pass"
