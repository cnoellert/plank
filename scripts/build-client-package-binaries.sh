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

for command_name in git make pkg-config qmake6 readelf realpath rg; do
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

# StationConnect has one qualified SDR 4:4:4 video profile and one windowed
# launcher mode. These are product invariants, not user preferences or CLI
# overrides.
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
rg -U -q 'addNewHostManually\(addressText\.text\.trim\(\),[[:space:]]*nicknameText\.text\.trim\(\)\)' \
  "$source_dir/app/gui/main.qml" || {
  echo "manual workstation dialog does not submit both address and nickname" >&2
  exit 1
}
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
echo "client_binary=${client_binary}"
echo "client_package_binary_gate=pass"
