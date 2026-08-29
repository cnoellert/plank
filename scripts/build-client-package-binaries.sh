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

for command_name in cargo cmp find git make mktemp nm pkg-config qmake6 readelf realpath rg rustc stat timeout; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done
[[ $(rustc --version) == "rustc 1.89.0 "* ]] || {
  echo "StationConnect datasmash requires rustc 1.89.0" >&2
  exit 1
}
[[ $(cargo --version) == "cargo 1.89.0 "* ]] || {
  echo "StationConnect datasmash requires cargo 1.89.0" >&2
  exit 1
}
datasmash_transport_dir="${repo_dir}/protocol/datasmash-transport"
for datasmash_input in \
  Cargo.toml \
  Cargo.lock \
  include/stationconnect_datasmash.h \
  src/lib.rs; do
  [[ -f ${datasmash_transport_dir}/${datasmash_input} ]] || {
    echo "datasmash transport input is unavailable: ${datasmash_input}" >&2
    exit 1
  }
done
cargo metadata --locked --offline --no-deps \
  --format-version 1 \
  --manifest-path "${datasmash_transport_dir}/Cargo.toml" >/dev/null
echo "client_datasmash_rust_input_gate=pass"
for required_datasmash_token in \
  'stationconnect-data-plane' \
  'Datasmash single-port transport (Experimental)' \
  '"&scDataPlane="' \
  'StationConnectDatasmashCertificateSha256' \
  'isCanonicalSha256Hex' \
  'startDatasmashDataPlane' \
  'sc_datasmash_native_video_receive' \
  'LiSubmitStationConnectVideoFrame' \
  'sc_datasmash_native_audio_receive' \
  'LiSubmitStationConnectAudioPacket' \
  'LiSetStationConnectNativeMediaEnabled' \
  'LiSetStationConnectControlPacketSender' \
  'datasmashControlPacketSender'; do
  rg -Fq "$required_datasmash_token" \
    "$source_dir/app" || {
    echo "client datasmash negotiation invariant is missing: ${required_datasmash_token}" >&2
    exit 1
  }
done
echo "client_datasmash_negotiation_gate=pass"
for required_audio_transport_token in \
  'LiSubmitStationConnectVideoFrame' \
  'LiSubmitStationConnectAudioPacket' \
  'StationConnectNativeMediaEnabled' \
  'STATIONCONNECT_VIDEO_FRAME_FLAG_KEY'; do
  rg -Fq "$required_audio_transport_token" \
    "$source_dir/moonlight-common-c/moonlight-common-c/src" || {
    echo "client native media transport invariant is missing: ${required_audio_transport_token}" >&2
    exit 1
  }
done
echo "client_datasmash_native_media_gate=pass"
for removed_media_bridge_token in \
  'StationConnectVideoPacketReceiver' \
  'StationConnectAudioPacketReceiver'; do
  if rg -Fq "$removed_media_bridge_token" \
    "$source_dir/moonlight-common-c/moonlight-common-c/src" \
    "$source_dir/app/streaming"; then
    echo "obsolete tunneled media bridge remains: ${removed_media_bridge_token}" >&2
    exit 1
  fi
done
echo "client_datasmash_legacy_media_bridge_absence_gate=pass"
for required_control_transport_token in \
  'StationConnectControlPacketSender' \
  'externalControlPacketSender' \
  'ptype == packetTypes[IDX_SET_VIDEO_BITRATE]' \
  'Failed to send StationConnect bitrate control packet over external transport'; do
  rg -Fq "$required_control_transport_token" \
    "$source_dir/moonlight-common-c/moonlight-common-c/src" || {
    echo "client external control transport invariant is missing: ${required_control_transport_token}" >&2
    exit 1
  }
done
echo "client_datasmash_control_sender_gate=pass"
for required_control_receiver_token in \
  'StationConnectControlPacketReceiver' \
  'externalControlPacketReceiver' \
  'External control packet source failed' \
  'sc_datasmash_native_data_receive' \
  'datasmashControlPacketReceiver'; do
  if ! rg -Fq "$required_control_receiver_token" \
    "$source_dir/moonlight-common-c/moonlight-common-c/src" \
    "$source_dir/app/streaming"; then
    echo "client external control receiver invariant is missing: ${required_control_receiver_token}" >&2
    exit 1
  fi
done
echo "client_datasmash_control_receiver_gate=pass"

package_version=$(<"${repo_dir}/packaging/VERSION")
[[ $package_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.datasmash$ ]] || {
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

if rg -n \
  'STATIONCONNECT_VPN_INTERFACE|isApprovedStationConnectRoute|approved VPN route' \
  "$source_dir/app"; then
  echo "client-side VPN route restriction is present in StationConnect" >&2
  exit 1
fi
echo "client_vpn_route_check_absence_gate=pass"

# StationConnect Client is launched explicitly from its desktop entry or
# command. It must not ship or manage a background user service or autostart
# entry.
[[ ! -e ${repo_dir}/packaging/systemd/stationconnect-client.service ]] || {
  echo "client systemd user service remains in package source" >&2
  exit 1
}
if find "$repo_dir/packaging" -path '*/autostart/*' -print -quit | rg -q .; then
  echo "client desktop autostart entry remains in package source" >&2
  exit 1
fi
if rg -n 'stationconnect-client\.service|deb-systemd-helper|systemctl[[:space:]]+--user' \
  "$repo_dir/packaging/deb/postinst" "$repo_dir/packaging/deb/postrm"; then
  echo "client maintainer scripts retain user-service or autostart handling" >&2
  exit 1
fi
echo "client_autostart_absence_gate=pass"

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

# A reconnect must prevent the raw-tablet worker from attaching while the
# replacement control stream is only partially initialized. A bounded attach
# acknowledgement timeout ensures a lost reply cannot leave reports disabled
# for the rest of the session.
for required_raw_hid_reconnect_token in \
  beginRawHidReconnect \
  finishRawHidReconnect \
  'm_Reconnecting.load()' \
  'Timed out waiting for exact Wacom host attachment; retrying'; do
  rg -Fq "$required_raw_hid_reconnect_token" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/streaming/input/input.cpp" \
    "$source_dir/app/streaming/input/linuxrawwacom.cpp" || {
    echo "client raw-HID reconnect barrier is missing: ${required_raw_hid_reconnect_token}" >&2
    exit 1
  }
done
echo "client_raw_hid_reconnect_gate=pass"

# First-generation Intuos Pro S/M/L USB interfaces require hid-wacom's real
# USB interface type, which Linux UHID cannot reproduce. Keep the complete
# PTH-x51 family on the existing normalized core-pen path while all newer
# in-scope Wacoms continue to use descriptor-driven exact raw-HID forwarding.
for required_wacom_generation_token in \
  'case 0x0314: // PTH-451' \
  'case 0x0315: // PTH-651' \
  'case 0x0317: // PTH-851' \
  'return StationConnectWacomTransport::NormalizedPen;' \
  'return StationConnectWacomTransport::ExactRawHid;' \
  'Using normalized pen transport for first-generation Intuos Pro'; do
  rg -Fq "$required_wacom_generation_token" \
    "$source_dir/app/streaming/input/input.cpp" \
    "$source_dir/app/streaming/input/linuxrawwacom.cpp" \
    "$source_dir/app/streaming/input/linuxrawwacom.h" || {
    echo "client Wacom generation transport invariant is missing: ${required_wacom_generation_token}" >&2
    exit 1
  }
done
echo "client_wacom_generation_transport_gate=pass"

# StationConnect uses one compositor-owned local cursor across the stream and
# toolbar. Exact host cursor images arrive on the encrypted control stream;
# the client must not fall back to synchronizing a cursor embedded in video.
for required_cursor_token in \
  'SC_CURSOR_WIRE_VERSION 1U' \
  'SC_CURSOR_MAX_CHUNK_SIZE (48U * 1024U)' \
  '0x5507, // Local cursor shape' \
  'ML_FF_LOCAL_CURSOR' \
  'LI_FF_LOCAL_CURSOR'; do
  rg -Fq "$required_cursor_token" "$client_common_dir" || {
    echo "client local-cursor protocol invariant is missing: ${required_cursor_token}" >&2
    exit 1
  }
done
for required_cursor_token in \
  handleRemoteCursorChunk \
  applyPendingRemoteCursor \
  SDL_CreateColorCursor \
  SDL_CODE_STATIONCONNECT_CURSOR; do
  rg -Fq "$required_cursor_token" \
    "$source_dir/app/streaming/input/input.cpp" \
    "$source_dir/app/streaming/input/input.h" \
    "$source_dir/app/streaming/session.cpp" || {
    echo "client local-cursor renderer invariant is missing: ${required_cursor_token}" >&2
    exit 1
  }
done
if rg -Fq 'forwardNativePointerPosition' "$source_dir/app/streaming"; then
  echo "client still forwards toolbar motion to synchronize a video cursor" >&2
  exit 1
fi
echo "client_local_cursor_gate=pass"

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

# The compact toolbar exposes one authoritative rolling 10-second peak of the
# FEC queue's one-second video data-packet loss samples. Do not substitute ENet
# control loss, post-FEC frame drops, or parity arrival counts: those measure
# different things and would either hide recovered network loss or report false
# loss on healthy streams.
for required_loss_token in \
  'ConnListenerVideoPacketLossUpdate' \
  'packetLossExpectedDataPackets' \
  'packetLossMissingDataPackets' \
  'queue->bufferDataPackets - queue->receivedDataPackets' \
  'getVideoDataPacketLossPercentage' \
  'videoPacketLossUpdate'; do
  rg -Fq "$required_loss_token" "$client_common_root/src" || {
    echo "video packet-loss telemetry invariant is missing: ${required_loss_token}" >&2
    exit 1
  }
done
for required_loss_ui_token in \
  'm_CurrentVideoPacketLossPercent' \
  'currentVideoPacketLossPercent' \
  'VideoPacketLossPeakWindow' \
  'kWindowMs = 10000' \
  'Incoming video packet loss (before FEC): %.2f%%' \
  'packetLossColor' \
  'const QColor blue(52, 132, 228)' \
  'const QColor green(52, 199, 110)' \
  'const QColor red(239, 88, 88)' \
  'clampedLoss <= 5.0' \
  '(clampedLoss - 5.0) / 5.0' \
  'QString("%1%").arg(m_PacketLossPercent' \
  'QRect(174, 16, 52, 17)' \
  'return toolbarLeft() + 229'; do
  rg -Fq "$required_loss_ui_token" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/streaming/session.h" \
    "$source_dir/app/streaming/videopacketlosswindow.h" \
    "$source_dir/app/streaming/stationconnecttoolbar.cpp" \
    "$source_dir/app/streaming/stationconnecttoolbar.h" \
    "$source_dir/app/streaming/video/ffmpeg.cpp" || {
    echo "video packet-loss toolbar invariant is missing: ${required_loss_ui_token}" >&2
    exit 1
  }
done
echo "client_video_packet_loss_indicator_gate=pass"

# The speed candidate keeps the accepted system-memory allocator as its
# default and exposes two developer-only alternatives through an environment
# selector. The mapped allocator is the measured reference experiment. The
# host-import allocator preserves cacheable FFmpeg reference frames while
# importing their allocations as Vulkan transfer buffers, avoiding the Intel
# driver's CPU linear-to-tiled upload path.
for required_frame_allocator_token in \
  'static int getMappedBuffer(AVCodecContext *context, AVFrame *frame, int flags);' \
  'static int getImportedHostBuffer(AVCodecContext *context, AVFrame *frame, int flags);' \
  'mappedContext.opaque = const_cast<pl_gpu*>(&renderer->m_Vulkan->gpu);' \
  'return pl_get_buffer2(&mappedContext, frame, flags);' \
  'STATIONCONNECT_VULKAN_FRAME_ALLOCATOR' \
  'requestedAllocator == "host-import"' \
  'bufferParams.import_handle = PL_HANDLE_HOST_PTR' \
  'Using pooled cacheable FFmpeg decode buffers imported into Vulkan' \
  'context->get_buffer2 = getMappedBuffer;' \
  'Using persistently mapped Vulkan decode buffers'; do
  rg -Fq "$required_frame_allocator_token" \
    "$source_dir/app/streaming/video/ffmpeg-renderers/plvk.cpp" \
    "$source_dir/app/streaming/video/ffmpeg-renderers/plvk.h" || {
    echo "Vulkan frame-allocator invariant is missing: ${required_frame_allocator_token}" >&2
    exit 1
  }
done
echo "client_vulkan_frame_allocator_gate=pass"

# Remote-workstation sessions capture OS-level key combinations by default so
# shortcuts such as Alt+Tab reach the host in both windowed and borderless mode.
rg -U -q 'settings\.value\(SER_CAPTURESYSKEYS,\n[[:space:]]+static_cast<int>\(CaptureSysKeysMode::CSK_ALWAYS\)\)' \
  "$source_dir/app/settings/streamingpreferences.cpp" || {
  echo "system keyboard shortcut capture does not default to Always" >&2
  exit 1
}
echo "client_system_shortcut_default_gate=pass"

# The bookmark owns the complete profile choice, including capture source,
# encoder backend, codec family, bit depth, and chroma. The client advertises
# only that selected format and selects an exact-format decoder internally.
if rg -n \
  'enableHdr|enableYUV444|supportsHdr|Enable HDR|Enable YUV 4:4:4|addToggleOption\("(hdr|yuv444)"|GUI display mode|uiDisplayMode|UIDisplayMode|UI_(WINDOWED|MAXIMIZED|FULLSCREEN)|uidisplaymode|startwindowed' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "optional HDR, YUV 4:4:4, or GUI display-mode controls are present in StationConnect client" >&2
  exit 1
fi
if rg -n \
  'VideoCodecConfig|videoCodecConfig|SER_VIDEOCFG|VCC_|video-codec|codecComboBox|resVCCTitle|Video codec' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "the obsolete global video codec preference is still present" >&2
  exit 1
fi
echo "client_global_video_codec_absence_gate=pass"
if rg -n \
  'm_SupportedVideoFormats\.append\(VIDEO_FORMAT_(H264\)|H265\)|H265_MAIN|AV1_MAIN)' \
  "$source_dir/app/streaming/session.cpp"; then
  echo "a 4:2:0 video profile is advertised by the StationConnect session" >&2
  exit 1
fi
for required_profile_token in \
  'SCVP_H264_8BIT_422' \
  'SCVP_H264_8BIT_444' \
  'SCVP_H264_10BIT_422' \
  'SCVP_H264_10BIT_444' \
  'SCVP_NVENC_H264_8BIT_444' \
  'SCVP_NVENC_HEVC_8BIT_444' \
  'SCVP_NVENC_HEVC_10BIT_444' \
  'selectedVideoFormat = VIDEO_FORMAT_H264_HIGH8_422;' \
  'selectedVideoFormat = VIDEO_FORMAT_H264_HIGH8_444;' \
  'selectedVideoFormat = VIDEO_FORMAT_H264_HIGH10_422;' \
  'selectedVideoFormat = VIDEO_FORMAT_H265_REXT8_444;' \
  'selectedVideoFormat = VIDEO_FORMAT_H265_REXT10_444;' \
  'int selectedVideoFormat = VIDEO_FORMAT_H264_HIGH10_444;' \
  'm_SupportedVideoFormats.append(selectedVideoFormat);'; do
  rg -Fq "$required_profile_token" \
    "$source_dir/app/settings/streamingpreferences.h" \
    "$source_dir/app/streaming/session.cpp" || {
    echo "StationConnect exact H.264 profile selection is missing: ${required_profile_token}" >&2
    exit 1
  }
done
if rg -n 'm_SupportedVideoFormats\.append\(VIDEO_FORMAT_' \
  "$source_dir/app/streaming/session.cpp"; then
  echo "StationConnect must advertise the one selected bookmark format, not fixed fallback formats" >&2
  exit 1
fi
for required_bookmark_profile_token in \
  '#define SER_VIDEOPROFILE "stationconnect-video-profile"' \
  'int stationConnectVideoProfile = 0;' \
  'settings.value(SER_VIDEOPROFILE,' \
  'settings.setValue(SER_VIDEOPROFILE, stationConnectVideoProfile);' \
  'stationConnectVideoProfile == that.stationConnectVideoProfile' \
  'stationConnectVideoProfile(int computerIndex) const' \
  'm_StationConnectVideoProfile'; do
  rg -Fq "$required_bookmark_profile_token" \
    "$source_dir/app/backend/nvcomputer.h" \
    "$source_dir/app/backend/nvcomputer.cpp" \
    "$source_dir/app/gui/computermodel.h" \
    "$source_dir/app/gui/computermodel.cpp" \
    "$source_dir/app/streaming/session.h" \
    "$source_dir/app/streaming/session.cpp" || {
    echo "StationConnect bookmark encoding profile is missing: ${required_bookmark_profile_token}" >&2
    exit 1
  }
done
for required_bookmark_profile_ui_token in \
  'addEncodingProfile' \
  'editEncodingProfile' \
  'computerModel.stationConnectVideoProfile(index)'; do
  rg -Fq "$required_bookmark_profile_ui_token" \
    "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" || {
    echo "StationConnect bookmark encoding-profile UI is missing: ${required_bookmark_profile_ui_token}" >&2
    exit 1
  }
done
if rg -n 'stationConnectVideoProfile|Encoding profile' \
  "$source_dir/app/gui/SettingsView.qml" \
  "$source_dir/app/settings/streamingpreferences.cpp"; then
  echo "encoding profile remains a global StationConnect preference" >&2
  exit 1
fi

# Every encoding profile owns an independent startup encoder target within each
# bookmark. The toolbar owns only a session-local copy, and no global or
# command-line bitrate source may compete with the bookmark/profile value.
for required_bookmark_bitrate_token in \
  '#define SER_STATIONCONNECT_PROFILE_BITRATES "stationconnect-profile-bitrates-kbps"' \
  'QVector<int> stationConnectProfileBitratesKbps =' \
  'stationConnectProfileBitratesFromVariantList(' \
  'stationConnectProfileBitratesToVariantList(' \
  'stationConnectProfileBitratesKbps ==' \
  'stationConnectProfileBitratesKbps(' \
  'stationConnectBitrateForProfile(' \
  'm_StationConnectBitrateKbps' \
  'm_StreamConfig.bitrate = m_StationConnectBitrateKbps;' \
  'StationConnectH264DefaultBitrateKbps = 80000' \
  'StationConnectHevcDefaultBitrateKbps = 50000'; do
  rg -Fq "$required_bookmark_bitrate_token" \
    "$source_dir/app/backend/nvcomputer.h" \
    "$source_dir/app/backend/nvcomputer.cpp" \
    "$source_dir/app/gui/computermodel.h" \
    "$source_dir/app/gui/computermodel.cpp" \
    "$source_dir/app/streaming/session.h" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/settings/streamingpreferences.h" || {
    echo "StationConnect bookmark bitrate invariant is missing: ${required_bookmark_bitrate_token}" >&2
    exit 1
  }
done
for required_bookmark_bitrate_ui_token in \
  addBitrateSlider \
  editBitrateSlider \
  'Startup encoder target:' \
  'Saved independently for each encoding profile. Toolbar adjustments apply only to the active session.' \
  'rememberProfileBitrate' \
  'computerModel.stationConnectProfileBitratesKbps(index)'; do
  rg -Fq "$required_bookmark_bitrate_ui_token" \
    "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" || {
    echo "StationConnect bookmark bitrate UI is missing: ${required_bookmark_bitrate_ui_token}" >&2
    exit 1
  }
done
if rg -n \
  'Q_PROPERTY\(int bitrateKbps|\bbitrateKbps MEMBER|#define SER_BITRATE "bitrate"|stationconnect-bitrate-kbps|getDefaultBitrate|StreamingPreferences\.bitrateKbps|m_Preferences\.bitrateKbps|preferences->bitrateKbps|addValueOption\("bitrate"' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "global or command-line bitrate configuration remains in StationConnect client" >&2
  exit 1
fi
if rg -n 'NVENC \(Experimental\)' \
  "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" \
  "$repo_dir/protocol/encoding-profiles.md"; then
  echo "NVENC encoding profiles must not be labeled Experimental" >&2
  exit 1
fi
for native_capture_label in \
  'Native X11/XShm — 10-bit (Experimental)'; do
  rg -Fq "$native_capture_label" \
    "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" || {
    echo "native X11 capture must retain its Experimental label" >&2
    exit 1
  }
done
for native_x264_profile_label in \
  'H.264 10-bit 4:4:4 (identity GBR) — x264'; do
  rg -Fq "$native_x264_profile_label" \
    "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" || {
    echo "native X11 profile must identify x264 explicitly" >&2
    exit 1
  }
done
for bookmark_layout_token in \
  'height: Math.min(1100, parent.height - 20)' \
  'id: unreachableActionComboBox' \
  'width: parent.width'; do
  rg -Fq "$bookmark_layout_token" \
    "$source_dir/app/gui/main.qml" "$source_dir/app/gui/PcView.qml" \
    "$source_dir/app/gui/SettingsView.qml" || {
    echo "StationConnect bookmark/settings layout invariant is missing: ${bookmark_layout_token}" >&2
    exit 1
  }
done
for audio_settings_token in \
  'Mute audio stream when the client is not the active window' \
  'Mutes streamed audio when you Alt+Tab out of the stream or click on a different window.'; do
  rg -Fq "$audio_settings_token" \
    "$source_dir/app/gui/SettingsView.qml" || {
    echo "StationConnect Audio Settings wording is missing: ${audio_settings_token}" >&2
    exit 1
  }
done
if rg -n 'Mute audio stream when Moonlight|Mutes Moonlight.s audio' \
  "$source_dir/app/gui/SettingsView.qml"; then
  echo "Moonlight branding remains in StationConnect Audio Settings" >&2
  exit 1
fi
if rg -n -U 'id: uiSettingsGroupBox\n[[:space:]]+parent: settingsColumn2' \
  "$source_dir/app/gui/SettingsView.qml"; then
  echo "UI Settings must remain in the left preference column" >&2
  exit 1
fi
echo "client_bookmark_bitrate_gate=pass"

for required_reconnect_wait_token in \
  'Waiting for previous workstation session to finish...' \
  'constexpr int RetryIntervalMs = 500;' \
  'constexpr int MaximumWaitMs = 30000;' \
  'sessionCleanupWaitChanged' \
  'cancelConnectionStart()'; do
  rg -Fq "$required_reconnect_wait_token" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/streaming/session.h" \
    "$source_dir/app/gui/StreamSegue.qml" || {
    echo "rapid reconnect client wait invariant is missing: ${required_reconnect_wait_token}" >&2
    exit 1
  }
done
echo "client_rapid_reconnect_wait_gate=pass"

for required_display_transition_token in \
  'display transition is still pending' \
  'authentication will be refreshed once' \
  'MaximumVirtualCanvasWidth = 8192' \
  'matchesRequestedHostLayout'; do
  rg -Fq "$required_display_transition_token" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/backend/outputtopology.h" || {
    echo "display-transition retry invariant is missing: ${required_display_transition_token}" >&2
    exit 1
  }
done
echo "client_display_transition_retry_gate=pass"

for required_retained_renderer_token in \
  'suspendForReconnect()' \
  'resumeAfterReconnect()' \
  'Paused FFmpeg decode while retaining the stream renderer' \
  'resumedRenderer ? "retained" : "recreated"'; do
  rg -Fq "$required_retained_renderer_token" \
    "$source_dir/app/streaming/session.cpp" \
    "$source_dir/app/streaming/video/decoder.h" \
    "$source_dir/app/streaming/video/ffmpeg.cpp" || {
    echo "retained reconnect renderer invariant is missing: ${required_retained_renderer_token}" >&2
    exit 1
  }
done
echo "client_retained_reconnect_renderer_gate=pass"

for required_reconnect_local_event_token in \
  'handleStationConnectLocalUserEvent' \
  'applyPendingRemoteCursor();' \
  'applyPendingTabletCursorActivation();' \
  'applyPendingRemoteCursorPosition();' \
  'one-shot pending latches'; do
  rg -Fq "$required_reconnect_local_event_token" \
    "$source_dir/app/streaming/session.cpp" || {
    echo "responsive reconnect local-event invariant is missing: ${required_reconnect_local_event_token}" >&2
    exit 1
  }
done
echo "client_reconnect_local_event_gate=pass"

for required_client_identity_token in \
  'QGuiApplication::setApplicationDisplayName("StationConnect Client");' \
  'SDL_SetAppMetadata("StationConnect Client",' \
  '"la.instinctual.StationConnect.Client");' \
  'app.setDesktopFileName("la.instinctual.StationConnect.Client");'; do
  rg -Fq "$required_client_identity_token" "$source_dir/app/main.cpp" || {
    echo "client application identity is missing: ${required_client_identity_token}" >&2
    exit 1
  }
done
if rg -n 'SDL_(AUDIO_DEVICE_APP_NAME|VIDEO_(WAYLAND|X11)_WMCLASS)' \
    "$source_dir/app/main.cpp"; then
  echo "client source still uses removed SDL2 application identity variables" >&2
  exit 1
fi
rg -Fq 'TARGET = stationconnect-client' "$source_dir/app/app.pro" || {
  echo "client build target is not branded stationconnect-client" >&2
  exit 1
}
approved_client_logo="$repo_dir/branding/assets/stationconnect_logo_circle.png"
runtime_client_logo="$source_dir/app/res/stationconnect-logo.png"
[[ -f $approved_client_logo ]] || {
  echo "approved StationConnect client logo is unavailable: ${approved_client_logo}" >&2
  exit 1
}
cmp --silent "$approved_client_logo" "$runtime_client_logo" || {
  echo "runtime client logo differs from the approved StationConnect artwork" >&2
  exit 1
}
echo "client_approved_logo_source_gate=pass"
client_desktop="$source_dir/app/deploy/linux/la.instinctual.StationConnect.Client.desktop"
client_appstream="$source_dir/app/deploy/linux/la.instinctual.StationConnect.Client.appdata.xml"
rg -Fxq 'Name=StationConnect Client' "$client_desktop" || {
  echo "client desktop display name is not StationConnect Client" >&2
  exit 1
}
rg -Fxq 'StartupWMClass=la.instinctual.StationConnect.Client' \
  "$client_desktop" || {
  echo "client desktop application ID is not canonical" >&2
  exit 1
}
rg -Fq '<id>la.instinctual.StationConnect.Client</id>' \
  "$client_appstream" || {
  echo "client AppStream application ID is not canonical" >&2
  exit 1
}
echo "client_application_id_gate=pass"

if rg -n \
  'VideoDecoderSelection|videoDecoderSelection|VDS_FORCE_|VDS_AUTO|video-decoder|DECODER_HINT|text:[[:space:]]*qsTr\("Video decoder"\)' \
  "$source_dir/app" --glob '!**/languages/**'; then
  echo "the removed global video decoder preference or override is still present" >&2
  exit 1
fi
for required_exact_decoder_token in \
  'DecoderSelectionMode::PreferExactHardwareThenSoftware' \
  'validateDecodedProfileFrame(frame, params)' \
  'frame->hw_frames_ctx->data' \
  'Exact profile validation rejected decoded format' \
  'Exact identity GBR validation rejected decoded color metadata'; do
  rg -Fq "$required_exact_decoder_token" "$source_dir/app" || {
    echo "exact decoder qualification is missing: ${required_exact_decoder_token}" >&2
    exit 1
  }
done
echo "client_exact_decoder_selection_gate=pass"

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

# Stream resolution belongs to each bookmark's Scaling policy. Scaled-Span
# derives its transport canvas from the active client display, while Native
# uses the selected host canvas exactly. Do not restore the old global
# resolution preference, saved width/height state, or CLI override path.
if rg -n \
  'stationConnectAutoResolution|SER_(WIDTH|HEIGHT)|Q_PROPERTY\(int (width|height)|add(Value|Flag)Option\("(resolution|720|1080|1440|4K)"|Use native client display resolution|Resolution and FPS' \
  "$source_dir/app" \
  --glob '!**/languages/**'; then
  echo "obsolete global stream-resolution preference is present" >&2
  exit 1
fi
for required_resolution_policy_token in \
  'text: qsTr("Frame rate")' \
  'text: qsTr("Window Mode")' \
  'resolution-policy=%s' \
  '"host-native" : "client-native"'; do
  rg -Fq "$required_resolution_policy_token" "$source_dir/app" || {
    echo "bookmark-owned resolution policy is missing: ${required_resolution_policy_token}" >&2
    exit 1
  }
done
echo "client_bookmark_resolution_policy_gate=pass"

# Manually entered workstations are persistent bookmarks even while offline.
# They retain both the entered address and editable nickname, then bind to the
# first server identity that successfully answers at that address.
for required_bookmark_token in \
  stationconnect-manual-bookmark \
  stationconnect-server-uuid \
  stationconnect-host-layout \
  stationconnect-virtual-mode-1 \
  stationconnect-virtual-mode-2 \
  stationconnect-scaling-mode \
  acceptsServerUuid \
  'Address or hostname' \
  Nickname; do
  rg -Fq "$required_bookmark_token" "$source_dir/app" || {
    echo "offline workstation bookmark invariant is missing: ${required_bookmark_token}" >&2
    exit 1
  }
done
rg -U -q 'addNewHostManually\(addressText\.text\.trim\(\),[[:space:]]*nicknameText\.text\.trim\(\),[[:space:]]*addHostLayout\.currentIndex,[[:space:]]*addVirtualMode1\.currentIndex,[[:space:]]*addVirtualMode2\.currentIndex,[[:space:]]*addScalingChoice\.currentIndex,[[:space:]]*addEncodingProfile\.model\.get\(' \
  "$source_dir/app/gui/main.qml" || {
  echo "manual workstation dialog does not submit address, nickname, host layout, independent virtual modes, scaling, and encoding profile" >&2
  exit 1
}
for required_bookmark_editor_token in \
  'Edit bookmark…' \
  editComputerBookmark \
  editManualBookmark \
  editScalingChoice; do
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

# Both bookmark dialogs consume the backend's canonical ordered mode list.
# Duplicated QML arrays can silently shift choice indices when a mode is added.
for bookmark_ui in \
  "$source_dir/app/gui/main.qml" \
  "$source_dir/app/gui/PcView.qml"; do
  rg -Fq 'property var virtualModeChoices: ComputerManager.stationConnectVirtualModeChoices()' \
    "$bookmark_ui" || {
    echo "bookmark resolution UI does not use the canonical backend list: ${bookmark_ui}" >&2
    exit 1
  }
done
for required_virtual_mode_token in \
  'Q_INVOKABLE QStringList stationConnectVirtualModeChoices() const;' \
  'QStringList choices = NvOutputTopology::qualifiedVirtualModes();' \
  'int hostLayout = 0, int virtualMode1 = 9' \
  'int virtualMode2 = 1' \
  'addVirtualMode1.currentIndex = 9' \
  'addVirtualMode2.currentIndex = 1' \
  'property int virtualMode1Index: 9' \
  'property int virtualMode2Index: 1' \
  'height: 1200' \
  'minimumHeight: 900'; do
  rg -Fq "$required_virtual_mode_token" \
    "$source_dir/app/backend/computermanager.h" \
    "$source_dir/app/backend/computermanager.cpp" \
    "$source_dir/app/gui/main.qml" \
    "$source_dir/app/gui/PcView.qml" || {
    echo "bookmark resolution-list invariant is missing: ${required_virtual_mode_token}" >&2
    exit 1
  }
done
rg -Fq 'QStringLiteral("5120x2160")' "$source_dir/app/backend/outputtopology.cpp" || {
  echo "5120x2160 is missing from the canonical bookmark mode list" >&2
  exit 1
}
if rg -Fq 'QStringLiteral("1280x720")' "$source_dir/app/backend/outputtopology.cpp" ||
   rg -Fq 'QStringLiteral("1280x1024")' "$source_dir/app/backend/outputtopology.cpp"; then
  echo "the canonical bookmark mode list still contains a removed mode" >&2
  exit 1
fi
echo "client_bookmark_resolution_list_gate=pass"

# Match Client is a client-side bookmark policy that resolves the active SDL3
# monitor inventory into an exact one- or two-output host request. The former
# inherited-host policy is intentionally absent because it made bookmark
# behavior depend on stale host state.
if rg -n 'ConfiguredHostLayout|Use the host.s configured layout' \
  "$source_dir/app" --glob '!**/languages/**'; then
  echo "inherited configured-host bookmark policy is present" >&2
  exit 1
fi
for required_match_client_token in \
  'MatchClientHostLayout' \
  'resolveClientDisplayLayout' \
  'Match client displays'; do
  rg -Fq "$required_match_client_token" "$source_dir/app" || {
    echo "match-client bookmark invariant is missing: ${required_match_client_token}" >&2
    exit 1
  }
done
echo "client_match_client_layout_gate=pass"

# A reachable host publishes its startup layout and explicit allowed layouts.
# Physical-startup hosts retain editable physical and temporary virtual choices;
# headless hosts reject only the physical choice. Offline bookmarks remain fully
# editable and are never silently rewritten when topology arrives.
for required_display_policy_token in \
  'stationConnectHostDisplayPolicy' \
  'displayPolicyKnown' \
  'allowedLayoutKinds' \
  'TemporaryPhysicalLayoutFeature' \
  'This headless workstation does not provide physical displays.' \
  'This workstation does not support the display layout selected by the bookmark.'; do
  rg -Fq "$required_display_policy_token" "$source_dir/app" || {
    echo "host display-policy invariant is missing: ${required_display_policy_token}" >&2
    exit 1
  }
done
if rg -Fq "normalized the bookmark to the host's physical-display policy" \
  "$source_dir/app"; then
  echo "client still silently rewrites bookmark display layouts" >&2
  exit 1
fi
echo "client_host_display_policy_gate=pass"

# Bookmark scaling applies to the complete host desktop. Native preserves a
# 1:1 transport canvas; Scaled-Span uses the qualified
# client-resolution fit. Individual remote-output selection is intentionally
# absent from the headless workflow.
if rg -n 'stationconnect-selected-output|selectedOutputId|scOutputId|stationConnectDisplayChoices|selectOutput\(|SingleOutputMode|SeparateDisplaysMode|Primary display|specific host monitor|Named host monitors' \
  "$source_dir/app" --glob '!**/languages/**'; then
  echo "remote-monitor selection is present in the StationConnect client" >&2
  exit 1
fi
for required_scaling_token in \
  'NativeScalingMode' \
  'stationConnectScalingChoice' \
  'Native (1:1 pixels)' \
  'Scaled-Span' \
  'Native scaling requires a valid host desktop pixel size.'; do
  rg -Fq "$required_scaling_token" "$source_dir/app" || {
    echo "bookmark scaling invariant is missing: ${required_scaling_token}" >&2
    exit 1
  }
done
echo "client_bookmark_scaling_gate=pass"

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
if rg -U -q 'id: networkSettingsGroupBox\n[[:space:]]+parent:' \
  "$source_dir/app/gui/SettingsView.qml"; then
  echo "Network Settings is explicitly reparented outside the right configuration column" >&2
  exit 1
fi
rg -U -q 'id: settingsColumn2(.|\n)*id: networkSettingsGroupBox' \
  "$source_dir/app/gui/SettingsView.qml" || {
  echo "Network Settings is not assigned to the right configuration column" >&2
  exit 1
}
echo "client_network_mtu_gate=pass"

# mDNS discovery is opt-in. Only the root-owned client policy may take
# precedence over the user preference and lock the corresponding UI control.
rg -Fq 'settings.value(SER_MDNS, false)' \
  "$source_dir/app/settings/streamingpreferences.cpp" || {
  echo "client mDNS discovery does not default to disabled" >&2
  exit 1
}
for required_mdns_token in \
  StationConnectClientPolicy \
  'network/mdns_discovery' \
  '/etc/stationconnect/stationconnect-client.conf' \
  mdnsDiscoveryManaged \
  '!StreamingPreferences.mdnsDiscoveryManaged'; do
  rg -Fq "$required_mdns_token" "$source_dir/app" || {
    echo "client managed mDNS invariant is missing: ${required_mdns_token}" >&2
    exit 1
  }
done
if rg -n 'STATIONCONNECT_MDNS_DISCOVERY|client\.env' \
  "$source_dir/app" \
  "$repo_dir/packaging/bin/stationconnect-client"; then
  echo "client retains the deprecated user-controlled mDNS environment policy" >&2
  exit 1
fi
client_policy="$repo_dir/packaging/config/stationconnect-client.conf"
rg -Fxq '[network]' "$client_policy" || {
  echo "client administrator policy is missing its network section" >&2
  exit 1
}
rg -Fxq '# mdns_discovery = false' "$client_policy" || {
  echo "client administrator policy does not document the optional managed value" >&2
  exit 1
}
if rg -q '^[[:space:]]*mdns_discovery[[:space:]]*=' "$client_policy"; then
  echo "client administrator policy locks mDNS in the default package" >&2
  exit 1
fi
for policy_test_file in \
  tests/stationconnectclientpolicy/stationconnectclientpolicy.pro \
  tests/stationconnectclientpolicy/test_stationconnectclientpolicy.cpp; do
  [[ -f ${source_dir}/${policy_test_file} ]] || {
    echo "client administrator policy test is missing: ${policy_test_file}" >&2
    exit 1
  }
done
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

policy_test_build=$(mktemp -d --tmpdir stationconnect-client-policy-test.XXXXXX)
cleanup_policy_test() {
  if [[ -d ${policy_test_build} ]]; then
    find "$policy_test_build" -xdev -depth -mindepth 1 -delete
    rmdir "$policy_test_build"
  fi
}
trap cleanup_policy_test EXIT
qmake6 "$source_dir/tests/stationconnectclientpolicy/stationconnectclientpolicy.pro" \
  -o "$policy_test_build/Makefile"
make -C "$policy_test_build" -j"$(nproc)"
QT_QPA_PLATFORM=offscreen "$policy_test_build/stationconnectclientpolicy"
cleanup_policy_test
trap - EXIT
echo "client_administrator_policy_test=pass"

export PKG_CONFIG_PATH="${ffmpeg_prefix}/lib/pkgconfig"
export LD_LIBRARY_PATH="${ffmpeg_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
[[ $(pkg-config --modversion libavcodec) == 63.* ]] || {
  echo "FFmpeg 9 libavcodec pkg-config metadata was not selected" >&2
  exit 1
}

mkdir -p "$build_dir"
(
  cd "$build_dir"
  qmake6 "$source_dir" CONFIG+=release CONFIG+=stationconnect-datasmash \
    "STATIONCONNECT_DATASMASH_TRANSPORT_DIR=${datasmash_transport_dir}" \
    "STATIONCONNECT_VERSION=${package_version}" \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CFLAGS+=-ffile-prefix-map=${source_dir}=../src" \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${build_dir}=." \
    "QMAKE_CXXFLAGS+=-ffile-prefix-map=${source_dir}=../src"
  make -j"$(nproc)"
)

client_binary="${build_dir}/app/stationconnect-client"
[[ -x ${client_binary} ]] || {
  echo "StationConnect client package binary was not produced" >&2
  exit 1
}
nm -C "$client_binary" | rg ' [Tt] sc_datasmash_abi_version$' >/dev/null || {
  echo "client binary does not link the datasmash transport ABI" >&2
  exit 1
}
rg -a -Fq 'StationConnect datasmash transport ABI' "$client_binary" || {
  echo "client binary does not report the inactive datasmash boundary" >&2
  exit 1
}
echo "client_datasmash_link_gate=pass"
if [[ -e ${build_dir}/app/moonlight ]]; then
  echo "client build still produced the superseded Moonlight runtime name" >&2
  exit 1
fi
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
