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

for command_name in cmake node npm realpath rg; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done
node_major=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
[[ $node_major =~ ^[0-9]+$ && $node_major -ge 22 ]] || {
  echo "Node.js 22 or newer is required to build the host web UI" >&2
  exit 1
}
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
  "$source_dir/src/platform/virtualhid_input.h" \
  "$source_dir/src_assets/common/assets/web/configs/tabs/Inputs.vue" \
  "$source_dir/src_assets/common/assets/web/config.html" \
  "$source_dir/src_assets/common/assets/web/apps.html"; then
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
  'SS_TOUCH_MAGIC|PSS_TOUCH_PACKET|platf::touch_update|create_touchscreen|supports_touchscreen|native_pen_touch' \
  "$source_dir/src/input.cpp" \
  "$source_dir/src/platform/virtualhid_input.cpp" \
  "$source_dir/src/platform/virtualhid_input.h" \
  "$source_dir/src/platform/linux/input/virtualhid.cpp" \
  "$source_dir/src/config.cpp" \
  "$source_dir/src/config.h" \
  "$source_dir/src_assets/common/assets/web/configs/tabs/Inputs.vue" \
  "$source_dir/src_assets/common/assets/web/config.html"; then
  echo "direct touchscreen support is present in StationConnect host" >&2
  exit 1
fi
echo "host_touchscreen_absence_gate=pass"

cmake -S "$source_dir" -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DSUNSHINE_ASSETS_DIR=share/stationconnect \
  -DCMAKE_C_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/gcc \
  -DCMAKE_CXX_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/g++ \
  -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc \
  -DFFMPEG_PREPARED_BINARIES="$ffmpeg_dir" \
  -DNPM="$(command -v npm)" \
  -DBUILD_DOCS=OFF \
  -DBUILD_TESTS=OFF \
  -DSUNSHINE_ENABLE_CUDA=ON \
  -DSUNSHINE_ENABLE_DRM=ON \
  -DSUNSHINE_ENABLE_KMS=OFF \
  -DSUNSHINE_ENABLE_KWIN=OFF \
  -DSUNSHINE_ENABLE_PORTAL=OFF \
  -DSUNSHINE_ENABLE_TRAY=OFF \
  -DSUNSHINE_ENABLE_VAAPI=ON \
  -DSUNSHINE_ENABLE_VULKAN=OFF \
  -DSUNSHINE_ENABLE_WAYLAND=OFF \
  -DSUNSHINE_ENABLE_X11=ON \
  -DSUNSHINE_ENABLE_XDG_PORTAL=OFF
cmake --build "$build_dir" --parallel "$build_jobs" \
  --target sunshine stationconnect-pam-broker stationconnect-host-supervisor web-ui

if rg -a -q '/usr/local/assets' "$build_dir/sunshine"; then
  echo "package binary contains the development asset path" >&2
  exit 1
fi
rg -a -q '/usr/share/stationconnect' "$build_dir/sunshine"
[[ -f ${build_dir}/assets/web/index.html ]] || {
  echo "host web UI was not produced" >&2
  exit 1
}
rg -q 'StationConnect Host' "$build_dir/assets/web/index.html" || {
  echo "host web UI is missing StationConnect branding" >&2
  exit 1
}
"${repo_dir}/scripts/audit-package-runtime.sh" "$build_dir/sunshine" >/dev/null

echo "host_web_node_version=$(node --version)"
echo "host_web_branding_gate=pass"
echo "host_binary=${build_dir}/sunshine"
echo "pam_broker_binary=${build_dir}/stationconnect-pam-broker"
echo "host_supervisor_binary=${build_dir}/stationconnect-host-supervisor"
echo "host_package_binary_gate=pass"
