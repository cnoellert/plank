#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
unit=${repo_dir}/packaging/systemd/stationconnect-host.service
pam_unit=${repo_dir}/packaging/systemd/stationconnect-pam-broker.service
pam_policy=${repo_dir}/packaging/pam/stationconnect-host
host_wacom_rule=${repo_dir}/packaging/udev/70-stationconnect-host-wacom.rules
spec=${repo_dir}/packaging/rpm/stationconnect-host.spec
builder=${repo_dir}/scripts/build-host-rpm.sh
firewalld_service=${repo_dir}/packaging/firewalld/stationconnect.xml

rg -Fxq 'ExecStart=/usr/libexec/stationconnect/stationconnect-host-supervisor' "$unit"
rg -Fxq 'WantedBy=multi-user.target' "$unit"
if rg -q '^EnvironmentFile=' "$unit"; then
  echo 'host service still loads a second environment configuration file' >&2
  exit 1
fi
rg -Fxq 'NoNewPrivileges=yes' "$unit"
rg -Fxq 'CapabilityBoundingSet=CAP_DAC_READ_SEARCH CAP_SYS_PTRACE' "$unit"
rg -Fxq 'ProtectHome=read-only' "$unit"
rg -Fxq 'RuntimeDirectory=stationconnect/host' "$unit"
rg -Fxq 'RuntimeDirectoryMode=0700' "$unit"
if rg -q '47990' "$firewalld_service"; then
  echo 'firewalld service still exposes the removed Web UI port' >&2
  exit 1
fi
rg -Fxq '  <port protocol="tcp" port="47989"/>' "$firewalld_service"
rg -Fxq '  <port protocol="udp" port="47989"/>' "$firewalld_service"
if rg -q '47984|48010|47998|47999|48000' "$firewalld_service"; then
  echo "retired StationConnect port remains in firewalld service" >&2
  exit 1
fi
rg -Fxq 'RuntimeDirectory=stationconnect/pam' "$pam_unit"
rg -Fxq 'RuntimeDirectoryMode=0700' "$pam_unit"
rg -Fxq 'ExecStart=/usr/libexec/stationconnect/stationconnect-pam-broker --socket /run/stationconnect/pam/auth.sock --config /etc/stationconnect/stationconnect-host.conf' "$pam_unit"
rg -Fq '/run/stationconnect/pam/auth.sock' \
  "$repo_dir/packaging/bin/stationconnect-host"
rg -Fxq 'account    include      system-auth' "$pam_policy"
rg -Fxq 'auth       substack     system-auth' "$pam_policy"
rg -Fxq 'session    optional     pam_keyinit.so force revoke' "$pam_policy"
rg -Fxq 'session    include      system-auth' "$pam_policy"
if rg -q '^[[:space:]]*(password|auth[[:space:]]+include[[:space:]]+postlogin|session[[:space:]]+include[[:space:]]+postlogin)' "$pam_policy"; then
  echo 'StationConnect PAM policy retains an unused password or postlogin stack' >&2
  exit 1
fi
if rg -q 'pam_succeed_if|ingroup|remote-desktop-users' "$pam_policy"; then
  echo 'StationConnect PAM policy still contains product-specific account authorization' >&2
  exit 1
fi
if rg -q '^CapabilityBoundingSet=.*CAP_(SETUID|SETGID|KILL)' "$unit"; then
  echo 'machine Sender retained obsolete identity-switching capabilities' >&2
  exit 1
fi
if rg -q '%h|graphical-session.target' "$unit"; then
  echo 'host unit still depends on a graphical user login' >&2
  exit 1
fi

rg -Fq '/usr/libexec/stationconnect/stationconnect-host-supervisor' "$spec"
rg -Fq '/usr/libexec/stationconnect/stationconnect-pam-broker' "$spec"
if rg -q '/usr/bin/stationconnect-(host-supervisor|pam-broker)' \
  "$unit" "$pam_unit" "$spec" "$builder"; then
  echo 'internal host service binaries remain exposed in /usr/bin' >&2
  exit 1
fi
rg -Fxq 'Requires:       xorg-x11-server-utils' "$spec"
rg -Fq '/usr/libexec/stationconnect/stationconnect-host' "$spec"
rg -Fq 'OUTPUT_NAME "stationconnect-host"' \
  "$repo_dir/host/sunshine-fork/cmake/targets/common.cmake"
rg -Fq '/usr/libexec/stationconnect/stationconnect-host' \
  "$repo_dir/packaging/bin/stationconnect-host"
rg -Fq '/usr/lib/systemd/system/stationconnect-host.service' "$spec"
rg -Fq '/usr/lib/systemd/system-preset/90-stationconnect.preset' "$spec"
rg -Fq 'systemctl preset stationconnect-display-prepare.service' "$spec"
rg -Fxq '%systemd_postun stationconnect-display-prepare.service' "$spec"
rg -Fxq '%systemd_postun_with_restart stationconnect-pam-broker.service stationconnect-host.service' "$spec"
if rg -n '^%systemd_postun_with_restart .*stationconnect-display-prepare\.service' "$spec"; then
  echo 'boot-only display preparation is restarted during package upgrades' >&2
  exit 1
fi
rg -Fq 'stationconnect-host-certificate' "$spec"
rg -Fq 'stationconnect-host-state' "$spec"
rg -Fq '/var/lib/stationconnect/stationconnect_state.json' "$spec"
rg -Fxq 'file_state = /var/lib/stationconnect/stationconnect_state.json' \
  "$repo_dir/packaging/config/stationconnect-host.conf"
rg -Fxq 'allow_root_login = false' \
  "$repo_dir/packaging/config/stationconnect-host.conf"
rg -Fxq '/etc/pam.d/stationconnect-host' "$spec"
test -f "$host_wacom_rule"
test ! -e "$repo_dir/packaging/udev/70-stationconnect-wacom.rules"
rg -Fq '/usr/lib/udev/rules.d/70-stationconnect-host-wacom.rules' "$spec"
if rg -Fq '/usr/lib/udev/rules.d/70-stationconnect-wacom.rules' "$spec"; then
  echo 'host RPM spec retains the ambiguous Wacom rule filename' >&2
  exit 1
fi
rg -Fxq '%dir %attr(0700,root,root) /etc/stationconnect/tls' "$spec"
rg -Fxq '%ghost %config(noreplace) %attr(0600,root,root) /etc/stationconnect/tls/key.pem' "$spec"
if rg -q 'stationconnect-auth|remote-desktop-users|/etc/pam\.d/remote-desktop|sysusers' \
  "$pam_unit" "$pam_policy" "$spec" \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"; then
  echo 'obsolete StationConnect authentication-group policy remains' >&2
  exit 1
fi
rg -Fq 'packaging/pam/stationconnect-host' "$builder"
rg -Fq 'packaging/udev/70-stationconnect-host-wacom.rules' "$builder"
if rg -q 'packaging/pam/remote-desktop|packaging/sysusers\.d' "$builder"; then
  echo 'host package builder still installs obsolete authentication-group files' >&2
  exit 1
fi
rg -Fq 'constexpr std::string_view pam_service = "stationconnect-host"' \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"
rg -Fq 'auth::load_broker_policy(config_path, policy_error)' \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"
rg -Fq 'if (username == "root" && !allow_root_login)' \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"
rg -Fq 'bool_f(vars, "allow_root_login", broker_allow_root_login)' \
  "$repo_dir/host/sunshine-fork/src/config.cpp"
rg -Fq 'chmod(path.parent_path().c_str(), 0700)' \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"
rg -Fq 'chmod(path.c_str(), 0600)' \
  "$repo_dir/host/sunshine-fork/src/auth/pam_broker.cpp"
if rg -Fq '/usr/lib/systemd/user/stationconnect-host.service' "$spec"; then
  echo 'RPM manifest still contains the obsolete host user unit' >&2
  exit 1
fi

rg -Fq 'refusing to package a dirty StationConnect source tree' "$builder"
rg -Fq 'stationconnect-host-supervisor' "$builder"
rg -Fq 'stationconnect-host-certificate' "$builder"
rg -Fq 'stationconnect-host-state' "$builder"
rg -Fq 'STATIONCONNECT_BOOST_SOURCE_DIR' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'project(Boost VERSION 1.89.0 LANGUAGES CXX)' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'FETCHCONTENT_SOURCE_DIR_BOOST' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_mouse_scroll_compat_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_num_lock_always_on_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'client_bookmark_resolution_policy_gate=pass' \
  "$repo_dir/scripts/build-client-package-binaries.sh"
rg -Fq 'client_wacom_generation_transport_gate=pass' \
  "$repo_dir/scripts/build-client-package-binaries.sh"
rg -Fq 'restrict_worker_capabilities' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'stage_pulse_cookie' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '/run/stationconnect/host/pulse-cookie' \
  "$repo_dir/host/sunshine-fork/src/session/session_context.cpp"
rg -Fq 'STATIONCONNECT_SESSION_CONTROL_FD' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
if rg -q 'STATIONCONNECT_(HOST_OPTIONS|MDNS_DISCOVERY)' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp" \
  "$repo_dir/host/sunshine-fork/src/main.cpp" \
  "$repo_dir/packaging/bin/stationconnect-host"; then
  echo 'legacy host environment configuration remains' >&2
  exit 1
fi
rg -Fq 'stationconnect_mdns_discovery' \
  "$repo_dir/host/sunshine-fork/src/config.cpp"
rg -Fxq 'stationconnect_mdns_discovery = false' \
  "$repo_dir/packaging/config/stationconnect-host.conf"
rg -Fq '/etc/stationconnect/stationconnect-host.conf' \
  "$repo_dir/packaging/bin/stationconnect-host"
[[ ! -e ${repo_dir}/packaging/config/stationconnect.conf ]]
if rg -n '/etc/stationconnect/stationconnect\.conf' \
  "$repo_dir/packaging/bin" \
  "$repo_dir/packaging/systemd" \
  "$repo_dir/packaging/rpm/stationconnect-host.spec" \
  "$repo_dir/host/sunshine-fork/src"; then
  echo 'ambiguous generic host configuration path remains' >&2
  exit 1
fi
if rg -n '^[[:space:]]*output_name[[:space:]]*=' \
  "$repo_dir/packaging/config/stationconnect-host.conf" ||
  rg -n \
    'video_config\.output_name|config::video\.output_name|"output_name",[[:space:]]*video\.output_name' \
    "$repo_dir/host/sunshine-fork/src" \
    "$repo_dir/host/sunshine-fork/tests" \
    --glob '*.{cpp,h}'; then
  echo 'legacy static capture-output selector remains' >&2
  exit 1
fi
rg -Fq 'session.output_name = *capture_name' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"
rg -Fq 'config.monitor.output_name = launch_session->span_desktop ?' \
  "$repo_dir/host/sunshine-fork/src/session_stream.cpp"
rg -Fq 'config.m_device_id = session.output_name' \
  "$repo_dir/host/sunshine-fork/src/display_device.cpp"
rg -Fq 'host_static_capture_selector_absence_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_global_video_selector_absence_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_rpm_global_video_selector_absence_gate=pass' \
  "$repo_dir/scripts/build-host-rpm.sh"
rg -Fq 'host_x264_config_section_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_complete_config_template_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_rpm_x264_config_section_gate=pass' \
  "$repo_dir/scripts/build-host-rpm.sh"
rg -Fxq '[x264-encoder]' \
  "$repo_dir/packaging/config/stationconnect-host.conf"
if rg -Fxq '[software-encoder]' \
  "$repo_dir/packaging/config/stationconnect-host.conf"; then
  echo 'packaged host configuration retains the obsolete software-encoder section' >&2
  exit 1
fi
if rg -n '^\[video\]$|^[[:space:]]*(capture|encoder)[[:space:]]*=' \
  "$repo_dir/packaging/config/stationconnect-host.conf"; then
  echo 'packaged host configuration still exposes global video selectors' >&2
  exit 1
fi
if rg -n \
  'config::video\.(capture|encoder)|std::string[[:space:]]+(capture|encoder);|string_f\(vars,[[:space:]]*"(capture|encoder)"' \
  "$repo_dir/host/sunshine-fork/src" \
  "$repo_dir/host/sunshine-fork/tests" \
  --glob '*.{cpp,h}'; then
  echo 'host source still contains global video selectors' >&2
  exit 1
fi
rg -Fq 'host_legacy_x11_capture_absence_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_upnp_absence_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_auth_group_absence_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_fixed_desktop_reservation_gate=pass' \
  "$repo_dir/scripts/build-host-package-binaries.sh"
rg -Fq 'host_rpm_fixed_desktop_gate=pass' \
  "$repo_dir/scripts/build-host-rpm.sh"
rg -Fq 'inline constexpr int desktop_app_id = 881448767' \
  "$repo_dir/host/sunshine-fork/src/process.h"
rg -Fq 'std::atomic<int> _app_id {0}' \
  "$repo_dir/host/sunshine-fork/src/process.h"
rg -Fq 'if(WIN32 OR APPLE)' \
  "$repo_dir/host/sunshine-fork/cmake/dependencies/Boost_Sunshine.cmake"
if rg -n 'apps\.json|file_apps|global_prep_cmd|Steam Big Picture|Low Res Desktop' \
  "$repo_dir/host/sunshine-fork/src" \
  "$repo_dir/host/sunshine-fork/src_assets" \
  "$repo_dir/host/sunshine-fork/cmake" \
  "$repo_dir/host/sunshine-fork/packaging" \
  "$repo_dir/host/sunshine-fork/docs"; then
  echo 'legacy host application catalog remains' >&2
  exit 1
fi
if rg -n 'run_command|request_process_group_exit|process_group_running|open_url' \
  "$repo_dir/host/sunshine-fork/src/platform/common.h" \
  "$repo_dir/host/sunshine-fork/src/platform/linux" \
  "$repo_dir/host/sunshine-fork/tests/integration"; then
  echo 'legacy Linux external-command launcher remains' >&2
  exit 1
fi
if [[ -e $repo_dir/host/sunshine-fork/src/upnp.cpp || \
      -e $repo_dir/host/sunshine-fork/src/upnp.h ]]; then
  echo 'UPnP implementation files remain' >&2
  exit 1
fi
if rg -n -i 'miniupnp|upnp' \
  "$repo_dir/host/sunshine-fork/src" \
  "$repo_dir/host/sunshine-fork/cmake" \
  "$repo_dir/host/sunshine-fork/scripts" \
  "$repo_dir/host/sunshine-fork/packaging" \
  "$repo_dir/host/sunshine-fork/docs" \
  "$repo_dir/host/sunshine-fork/.github" \
  "$repo_dir/host/sunshine-fork/docker" \
  "$repo_dir/packaging" \
  --glob '!**/third-party/**'; then
  echo 'UPnP or miniupnpc capability remains' >&2
  exit 1
fi
rg -Fq 'host_rpm_upnp_absence_gate=pass' \
  "$repo_dir/scripts/build-host-rpm.sh"
rg -Fq 'restarting the StationConnect media worker for fresh X11/NvFBC state' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'stop_worker(worker);' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'Scheduled StationConnect display transition from ' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'StationConnect live display transition completed for UID' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
if ! rg -Uq \
  '(?s)X509_digest\(certificate, EVP_sha256\(\).*?util::hex_vec\(std::vector<std::uint8_t>\(.*?\), true\);' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"; then
  echo 'datasmash certificate pin is not emitted in conventional TLS byte order' >&2
  exit 1
fi
rg -Fq 'Temporary StationConnect physical-display lease acquired for UID' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '/usr/libexec/stationconnect/stationconnect-display-prepare' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fxq 'ReadWritePaths=/etc/X11/xorg.conf.d' \
  "$repo_dir/packaging/systemd/stationconnect-host.service"
rg -Fq 'Only the active desktop user may change its display layout' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"
rg -Fq 'The requested display layout is not supported by this workstation' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"
rg -Fq 'persistent virtual display transitions are disabled by display.startup_layout' \
  "$repo_dir/packaging/bin/stationconnect-display-prepare"
rg -Fq 'Restored the exact pre-session physical NVIDIA MetaMode' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'safe native physical output' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
if rg -q 'reboot|systemctl_path, \{"restart", "display-manager' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"; then
  echo 'physical display recovery retained a reboot or display-manager restart path' >&2
  exit 1
fi
rg -Fq 'layout_arguments(request.mode_1, request.mode_2)' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '"--fb", std::to_string(canvas_width) + "x" + std::to_string(canvas_height)' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'Virtual ${maximum_canvas_width} ${maximum_canvas_height}' \
  "$repo_dir/packaging/bin/stationconnect-display-prepare"
rg -Fq 'maximum_canvas_width=8192' \
  "$repo_dir/packaging/bin/stationconnect-display-prepare"
rg -Fq '"--rate", "60"' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '"--set", "non-desktop", "0"' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '"--off", "--set", "non-desktop", "1"' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'visibility_session_id != selected->id' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'visibility_session_id = selected->id' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'constexpr std::string_view systemd_run_path = "/usr/bin/systemd-run"' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '"--uid=" + account.name' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '"--property=NoNewPrivileges=yes"' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
if rg -q 'set(uid|gid|groups)\(' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"; then
  echo "host supervisor must delegate user-command identity to systemd" >&2
  exit 1
fi
if rg -q 'AllowNonEdidModes|--newmode|--addmode|StationConnect-' \
  "$repo_dir/packaging/bin/stationconnect-display-prepare" \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"; then
  echo 'host retained non-EDID live mode injection' >&2
  exit 1
fi
if rg -q 'stationconnect_authentication|/pair|pair_session_t|pairing' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp" \
  "$repo_dir/host/sunshine-fork/src/nvhttp.h"; then
  echo 'host retained legacy PIN/certificate pairing code' >&2
  exit 1
fi
rg -Fq 'StationConnect PAM broker is unavailable; refusing to start session negotiation' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"
rg -Fq '/run/stationconnect/pam/auth.sock' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"

client_session="$repo_dir/client/moonlight-qt-fork/app/streaming/session.cpp"
client_http="$repo_dir/client/moonlight-qt-fork/app/backend/nvhttp.cpp"
client_manager="$repo_dir/client/moonlight-qt-fork/app/backend/computermanager.cpp"
client_input="$repo_dir/client/moonlight-qt-fork/app/streaming/input/input.cpp"
client_raw_wacom="$repo_dir/client/moonlight-qt-fork/app/streaming/input/linuxrawwacom.cpp"
rg -Fq 'StationConnect transport ended' "$client_session"
rg -Fq 'for (int attempt = 1; !m_ReconnectCancelled.load(); ++attempt)' "$client_session"
rg -Fq 'constexpr int RetryDelayMs = 1000' "$client_session"
rg -Fq 'replacement worker has no app to resume' "$client_session"
rg -Fq 'worker already has an active Desktop stream' "$client_session"
rg -Fq 'm_InputHandler->beginRawHidReconnect();' "$client_session"
rg -Fq 'm_InputHandler->finishRawHidReconnect();' "$client_session"
rg -Fq 'suspendForReconnect();' "$client_session"
rg -Fq 'resumeAfterReconnect();' "$client_session"
rg -Fq 'handleStationConnectLocalUserEvent' "$client_session"
rg -Fq 'one-shot pending latches' "$client_session"
rg -Fq 'display transition is still pending' "$client_session"
rg -Fq 'authentication will be refreshed once' "$client_session"
rg -Fq "response.trimmed().startsWith(QLatin1Char('<'))" "$client_http"
rg -Fq 'verifyResponseStatus(response);' "$client_http"
rg -Fq 'm_LinuxRawWacomInput->beginReconnect();' "$client_input"
rg -Fq 'm_LinuxRawWacomInput->finishReconnect();' "$client_input"
rg -Fq 'release(false);' "$client_raw_wacom"
rg -Fq 'm_AttachFailed.store(false);' "$client_raw_wacom"
rg -Fq 'm_CanReconnect.store(false)' "$client_session"
rg -Fq 'rememberStationConnectReconnectCredentials' "$client_manager"
