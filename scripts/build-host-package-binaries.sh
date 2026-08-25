#!/usr/bin/env bash

set -euo pipefail

if (($# > 2)); then
  echo "usage: $0 [BUILD_DIR] [PREPARED_FFMPEG_DIR]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="${repo_dir}/host/sunshine-fork"
build_dir=$(realpath -m -- "${1:-${repo_dir}/build/package-host}")
ffmpeg_dir=$(realpath -m -- "${2:-${source_dir}/cmake-build-ffmpeg-x264rgb-install/ffmpeg}")
build_jobs=${STATIONCONNECT_BUILD_JOBS:-8}
[[ $build_jobs =~ ^[1-9][0-9]*$ ]] || {
  echo "invalid host build job count: ${build_jobs}" >&2
  exit 1
}

for command_name in cmake nm realpath rg; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done
for compiler in \
  /opt/rh/gcc-toolset-14/root/usr/bin/gcc \
  /opt/rh/gcc-toolset-14/root/usr/bin/g++ \
  /usr/local/cuda/bin/nvcc; do
  [[ -x ${compiler} ]] || {
    echo "required compiler is unavailable: ${compiler}" >&2
    exit 1
  }
done
[[ -f ${ffmpeg_dir}/lib/libavcodec.a ]] || {
  echo "prepared host FFmpeg tree is unavailable: ${ffmpeg_dir}" >&2
  exit 1
}

# StationConnect's Rocky host accepts workstation keyboard, mouse, normalized
# pen, and raw-HID Wacom input only. Keep controller packet routing, feedback,
# Linux virtual-gamepad integration, launch metadata, and configuration UI out
# of the production host even though the shared libvirtualhid dependency
# remains.
if rg -n \
  'MULTI_CONTROLLER_MAGIC|SS_CONTROLLER_(ARRIVAL|TOUCH|MOTION|BATTERY)_MAGIC|gamepad_feedback|terminate_gamepads|probe_gamepads' \
  "$source_dir/src/input.cpp" "$source_dir/src/input.h" \
  "$source_dir/src/stream.cpp" "$source_dir/src/globals.h"; then
  echo "controller packet routing or feedback is present in StationConnect host source" >&2
  exit 1
fi
if rg -n -i \
  'gamepad|controller|gcmap' \
  "$source_dir/src/platform/linux/input/virtualhid.cpp" \
  "$source_dir/src/platform/virtualhid_input.cpp" \
  "$source_dir/src/platform/virtualhid_input.h"; then
  echo "Linux gamepad integration or host controller configuration is present" >&2
  exit 1
fi
[[ ! -e ${source_dir}/tests/unit/platform/test_virtualhid_input.cpp ]] || {
  echo "gamepad-specific host tests are present" >&2
  exit 1
}
echo "host_gamepad_absence_gate=pass"

if rg -n \
  'enable_sops|SUNSHINE_CLIENT_ENABLE_SOPS|resource\["\^/cancel\$"\]|root\.cancel' \
  "$source_dir/src" \
  --glob '*.{cpp,h}'; then
  echo "legacy client-controlled display or remote app cancellation is present in StationConnect host" >&2
  exit 1
fi
echo "host_remote_control_absence_gate=pass"

if rg -n \
  'root\.mac|get_mac_address|Unable to find MAC address' \
  "$source_dir/src" \
  --glob '*.{cpp,h,mm}'; then
  echo "Wake-on-LAN MAC metadata is present in StationConnect host source" >&2
  exit 1
fi
echo "host_wake_on_lan_absence_gate=pass"

for required_pc_range_token in \
  'av_color_range_from_name(' \
  'sunshine_colorspace.full_range ? "pc" : "tv"' \
  'colorspace.full_range ? "PC" : "TV"'; do
  rg -Fq "$required_pc_range_token" \
    "$source_dir/src/video_colorspace.cpp" "$source_dir/src/video.cpp" || {
    echo "StationConnect PC/full-range encoder terminology is missing: ${required_pc_range_token}" >&2
    exit 1
  }
done
if rg -n 'Color range:.*JPEG|Color range:.*MPEG' "$source_dir/src/video.cpp"; then
  echo "legacy JPEG/MPEG color-range terminology remains in the StationConnect encoder log" >&2
  exit 1
fi
echo "host_pc_color_range_gate=pass"

if rg -n \
  'SS_TOUCH_MAGIC|PSS_TOUCH_PACKET|platf::touch_update|create_touchscreen|supports_touchscreen|native_pen_touch' \
  "$source_dir/src/input.cpp" \
  "$source_dir/src/platform/virtualhid_input.cpp" \
  "$source_dir/src/platform/virtualhid_input.h" \
  "$source_dir/src/platform/linux/input/virtualhid.cpp" \
  "$source_dir/src/config.cpp" \
  "$source_dir/src/config.h"; then
  echo "direct touchscreen support is present in StationConnect host" >&2
  exit 1
fi
echo "host_touchscreen_absence_gate=pass"

# Losing client-window focus suspends raw-HID transport without destroying the
# host UHID/XInput endpoints. Stable endpoint identity prevents applications
# such as Flame from retaining a stale stylus/eraser device ID after refocus.
host_common_dir="${source_dir}/third-party/moonlight-common-c/src"
for required_raw_hid_token in \
  '#define SC_RAW_HID_WIRE_VERSION 2U' \
  'SC_RAW_HID_SUSPEND = 13'; do
  rg -Fq "$required_raw_hid_token" "$host_common_dir" || {
    echo "host raw-HID focus-suspend protocol invariant is missing: ${required_raw_hid_token}" >&2
    exit 1
  }
done
rg -q '#define[[:space:]]+LI_FF_RAW_HID_FOCUS_SUSPEND[[:space:]]+0x20' \
  "$host_common_dir/Limelight.h" || {
  echo "host raw-HID focus-suspend feature bit is missing" >&2
  exit 1
}
for required_raw_hid_token in \
  raw_hid_focus_suspend \
  SC_RAW_HID_SUSPEND \
  'Suspended raw HID tablet transport while retaining endpoints'; do
  rg -Fq "$required_raw_hid_token" \
    "$source_dir/src/platform/common.h" \
    "$source_dir/src/platform/linux/input/virtualhid.cpp" \
    "$source_dir/src/raw_hid_tablet.cpp" || {
    echo "host raw-HID endpoint-preservation invariant is missing: ${required_raw_hid_token}" >&2
    exit 1
  }
done
echo "host_raw_hid_focus_suspend_gate=pass"

# Exact raw-HID and normalized pen-tablet backends must never coexist after a
# raw group attaches. Flame otherwise applies Tablet Margins to the inactive
# generic device while pressure arrives from the exact Wacom endpoint.
for required_tablet_ownership_token in \
  sync_tablet_backend \
  set_normalized_pen_enabled \
  has_endpoints \
  'Exact raw HID tablet active; removed normalized pen fallback' \
  ExactRawTabletSuppressesNormalizedFallbackUntilDetach; do
  rg -Fq "$required_tablet_ownership_token" \
    "$source_dir/src/input.cpp" \
    "$source_dir/src/platform/virtualhid_input.cpp" \
    "$source_dir/src/raw_hid_tablet.cpp" \
    "$source_dir/tests/unit/test_input.cpp" || {
    echo "host raw/normalized tablet ownership invariant is missing: ${required_tablet_ownership_token}" >&2
    exit 1
  }
done
echo "host_raw_hid_fallback_exclusion_gate=pass"

# StationConnect keeps every host runtime setting in one Sunshine config file.
# mDNS advertisement remains opt-in and defaults to disabled there.
for required_mdns_token in \
  stationconnect_mdns_discovery \
  'StationConnect mDNS advertisement is disabled'; do
  rg -Fq "$required_mdns_token" "$source_dir/src/main.cpp" || {
    echo "host mDNS default-off invariant is missing: ${required_mdns_token}" >&2
    exit 1
  }
done
if rg -q 'STATIONCONNECT_(HOST_OPTIONS|MDNS_DISCOVERY)' \
  "$source_dir/src/main.cpp" \
  "$source_dir/src/session/host_supervisor.cpp" \
  "$repo_dir/packaging/bin/stationconnect-host" \
  "$repo_dir/packaging/systemd/stationconnect-host.service" \
  "$repo_dir/packaging/config/stationconnect.conf"; then
  echo "legacy host environment configuration is still present" >&2
  exit 1
fi
rg -Fxq 'stationconnect_mdns_discovery = false' \
  "$repo_dir/packaging/config/stationconnect.conf" || {
  echo "host mDNS configuration does not default to disabled" >&2
  exit 1
}
echo "host_mdns_default_off_gate=pass"

[[ ! -e ${repo_dir}/packaging/config/host.env ]] || {
  echo "legacy host.env remains in the package source" >&2
  exit 1
}
rg -Fq '/etc/stationconnect/stationconnect.conf' \
  "$repo_dir/packaging/bin/stationconnect-host"
echo "host_single_config_gate=pass"

# Virtual-display preparation augments the Autodesk Xorg baseline before GDM.
# It is opt-in, bounded to qualified layouts, and may not reconfigure a live
# display manager.
for required_display_token in \
  'virtual_outputs = off' \
  'virtual_mode_1 = 3840x2160' \
  'virtual_mode_2 = 3840x2160'; do
  rg -Fq "$required_display_token" \
    "$repo_dir/packaging/config/stationconnect.conf" || {
    echo "host display default is missing: ${required_display_token}" >&2
    exit 1
  }
done
for required_display_token in \
  'Before=display-manager.service' \
  'ExecStart=/usr/libexec/stationconnect/stationconnect-display-prepare' \
  'ReadWritePaths=/etc/X11/xorg.conf.d'; do
  rg -Fxq "$required_display_token" \
    "$repo_dir/packaging/systemd/stationconnect-display-prepare.service" || {
    echo "host display-preparation unit invariant is missing: ${required_display_token}" >&2
    exit 1
  }
done
for required_display_token in \
  'off|single|dual-horizontal' \
  'virtual_outputs == single' \
  'refusing to change the display topology while the display manager is active'; do
  rg -Fq "$required_display_token" \
    "$repo_dir/packaging/bin/stationconnect-display-prepare" || {
    echo "host display-preparation helper invariant is missing: ${required_display_token}" >&2
    exit 1
  }
done
echo "host_headless_display_default_off_gate=pass"

rg -Fxq \
  'X-StationConnect-ApplicationId=la.instinctual.StationConnect.Host' \
  "$repo_dir/packaging/systemd/stationconnect-host.service" || {
  echo "host systemd metadata does not carry the canonical application ID" >&2
  exit 1
}
echo "host_application_id_gate=pass"

# Host runtime diagnostics are written privately to a bounded persistent file
# while stdout remains attached to journald. systemd owns the writable log
# directory; the single administrator configuration file owns the log path.
rg -Fxq 'log_path = /var/log/stationconnect/stationconnect-host.log' \
  "$repo_dir/packaging/config/stationconnect.conf" || {
  echo "host persistent log path is not configured" >&2
  exit 1
}
for required_log_directory_token in \
  'LogsDirectory=stationconnect' \
  'LogsDirectoryMode=0700'; do
  rg -Fxq "$required_log_directory_token" \
    "$repo_dir/packaging/systemd/stationconnect-host.service" || {
    echo "host private systemd log directory invariant is missing: ${required_log_directory_token}" >&2
    exit 1
  }
done
for required_log_rotation_token in \
  'retained_log_file_count {10}' \
  'max_log_file_size {10U * 1024U * 1024U}' \
  'rotating_file_stream'; do
  rg -Fq "$required_log_rotation_token" \
    "$source_dir/src/logging.h" "$source_dir/src/logging.cpp" || {
    echo "host bounded log rotation invariant is missing: ${required_log_rotation_token}" >&2
    exit 1
  }
done
echo "host_persistent_logging_gate=pass"

cmake -S "$source_dir" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DSUNSHINE_ASSETS_DIR=share/stationconnect \
  -DCMAKE_C_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/gcc \
  -DCMAKE_CXX_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/g++ \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
  -DFFMPEG_PREPARED_BINARIES="$ffmpeg_dir" \
  -DBUILD_DOCS=OFF \
  -DBUILD_TESTS=OFF \
  -DSUNSHINE_ENABLE_CUDA=ON \
  -DSUNSHINE_ENABLE_DRM=ON \
  -DSUNSHINE_ENABLE_KMS=OFF \
  -DSUNSHINE_ENABLE_KWIN=OFF \
  -DSUNSHINE_ENABLE_PORTAL=OFF \
  -DSUNSHINE_ENABLE_VAAPI=ON \
  -DSUNSHINE_ENABLE_VULKAN=OFF \
  -DSUNSHINE_ENABLE_WAYLAND=OFF \
  -DSUNSHINE_ENABLE_X11=ON \
  -DSUNSHINE_ENABLE_XDG_PORTAL=OFF
cmake --build "$build_dir" --parallel "$build_jobs" \
  --target sunshine stationconnect-pam-broker stationconnect-host-supervisor

if rg -a -q '/usr/local/assets' "$build_dir/stationconnect-host"; then
  echo "package binary contains the development asset path" >&2
  exit 1
fi
rg -a -q '/usr/share/stationconnect' "$build_dir/stationconnect-host"
[[ ! -d ${build_dir}/assets/web ]] || {
  echo "host Web UI assets were produced" >&2
  exit 1
}
if nm -C "$build_dir/stationconnect-host" | rg -q 'confighttp::'; then
  echo "host binary still contains the configuration HTTP server" >&2
  exit 1
fi
if rg -a -q 'Sunshine - Web UI|Configuration UI available at' "$build_dir/stationconnect-host"; then
  echo "host binary still contains Web UI runtime paths" >&2
  exit 1
fi
if nm -C "$build_dir/stationconnect-host" | rg -q 'nvhttp::(pair|pin|unpair_client|getservercert|clientchallenge|clientpairingsecret)'; then
  echo "host binary still contains legacy pairing code" >&2
  exit 1
fi

for required_reconnect_token in \
  'std::mutex session_start_mutex' \
  'rtsp_stream::session_count() == 0' \
  'rtsp_stream::launch_session_pending()' \
  'Clearing orphaned StationConnect Desktop reservation before launch'; do
  rg -Fq "$required_reconnect_token" \
    "$source_dir/src/nvhttp.cpp" "$source_dir/src/rtsp.cpp" \
    "$source_dir/src/rtsp.h" || {
    echo "rapid reconnect host cleanup invariant is missing: ${required_reconnect_token}" >&2
    exit 1
  }
done
echo "host_rapid_reconnect_cleanup_gate=pass"

"${repo_dir}/scripts/audit-package-runtime.sh" "$build_dir/stationconnect-host" >/dev/null

echo "host_web_ui_absence_gate=pass"
echo "host_binary=${build_dir}/stationconnect-host"
echo "pam_broker_binary=${build_dir}/stationconnect-pam-broker"
echo "host_supervisor_binary=${build_dir}/stationconnect-host-supervisor"
echo "host_package_binary_gate=pass"
