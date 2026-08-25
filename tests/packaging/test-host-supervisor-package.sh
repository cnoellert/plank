#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
unit=${repo_dir}/packaging/systemd/stationconnect-host.service
pam_unit=${repo_dir}/packaging/systemd/stationconnect-pam-broker.service
spec=${repo_dir}/packaging/rpm/stationconnect-host.spec
builder=${repo_dir}/scripts/build-host-rpm.sh
firewalld_service=${repo_dir}/packaging/firewalld/stationconnect.xml

rg -Fxq 'ExecStart=/usr/bin/stationconnect-host-supervisor' "$unit"
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
rg -Fxq 'RuntimeDirectory=stationconnect/pam' "$pam_unit"
rg -Fxq 'ExecStart=/usr/bin/stationconnect-pam-broker --socket /run/stationconnect/pam/auth.sock --group stationconnect-auth' "$pam_unit"
rg -Fq '/run/stationconnect/pam/auth.sock' \
  "$repo_dir/packaging/bin/stationconnect-host"
if rg -q '^CapabilityBoundingSet=.*CAP_(SETUID|SETGID|KILL)' "$unit"; then
  echo 'machine Sender retained obsolete identity-switching capabilities' >&2
  exit 1
fi
if rg -q '%h|graphical-session.target' "$unit"; then
  echo 'host unit still depends on a graphical user login' >&2
  exit 1
fi

rg -Fq '/usr/bin/stationconnect-host-supervisor' "$spec"
rg -Fq '/usr/libexec/stationconnect/stationconnect-host' "$spec"
rg -Fq 'OUTPUT_NAME "stationconnect-host"' \
  "$repo_dir/host/sunshine-fork/cmake/targets/common.cmake"
rg -Fq '/usr/libexec/stationconnect/stationconnect-host' \
  "$repo_dir/packaging/bin/stationconnect-host"
rg -Fq '/usr/lib/systemd/system/stationconnect-host.service' "$spec"
rg -Fq '/usr/lib/systemd/system-preset/90-stationconnect.preset' "$spec"
rg -Fq '%sysusers_create stationconnect.conf' "$spec"
rg -Fq 'stationconnect-host-certificate' "$spec"
rg -Fq 'stationconnect-host-state' "$spec"
rg -Fq '/var/lib/stationconnect/stationconnect_state.json' "$spec"
rg -Fxq 'file_state = /var/lib/stationconnect/stationconnect_state.json' \
  "$repo_dir/packaging/config/stationconnect.conf"
if rg -Fq '/usr/lib/systemd/user/stationconnect-host.service' "$spec"; then
  echo 'RPM manifest still contains the obsolete host user unit' >&2
  exit 1
fi

rg -Fq 'refusing to package a dirty StationConnect source tree' "$builder"
rg -Fq 'stationconnect-host-supervisor' "$builder"
rg -Fq 'stationconnect-host-certificate' "$builder"
rg -Fq 'stationconnect-host-state' "$builder"
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
  "$repo_dir/packaging/config/stationconnect.conf"
rg -Fq '/etc/stationconnect/stationconnect.conf' \
  "$repo_dir/packaging/bin/stationconnect-host"
rg -Fq 'restarting the StationConnect media worker for fresh X11/NvFBC state' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'stop_worker(worker);' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'Scheduled StationConnect display transition from ' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'StationConnect live display transition completed for UID' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq '/usr/libexec/stationconnect/stationconnect-display-prepare' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fxq 'ReadWritePaths=/etc/X11/xorg.conf.d' \
  "$repo_dir/packaging/systemd/stationconnect-host.service"
rg -Fq 'Only the active desktop user may change its display layout' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp"
rg -Fq 'layout_arguments(request.mode_1, request.mode_2)' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'Option "ModeValidation" "AllowNonEdidModes"' \
  "$repo_dir/packaging/bin/stationconnect-display-prepare"
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
client_manager="$repo_dir/client/moonlight-qt-fork/app/backend/computermanager.cpp"
client_input="$repo_dir/client/moonlight-qt-fork/app/streaming/input/input.cpp"
client_raw_wacom="$repo_dir/client/moonlight-qt-fork/app/streaming/input/linuxrawwacom.cpp"
rg -Fq 'StationConnect transport ended' "$client_session"
rg -Fq 'MaximumAttempts = 20' "$client_session"
rg -Fq 'replacement worker has no app to resume' "$client_session"
rg -Fq 'worker already has an active Desktop stream' "$client_session"
rg -Fq 'm_InputHandler->resetRawHidAfterReconnect();' "$client_session"
rg -Fq 'suspendForReconnect();' "$client_session"
rg -Fq 'resumeAfterReconnect();' "$client_session"
rg -Fq 'display transition is still pending' "$client_session"
rg -Fq 'authentication will be refreshed once' "$client_session"
rg -Fq 'm_LinuxRawWacomInput->resetAfterReconnect();' "$client_input"
rg -Fq 'release(false);' "$client_raw_wacom"
rg -Fq 'm_AttachFailed.store(false);' "$client_raw_wacom"
rg -Fq 'm_CanReconnect.store(false)' "$client_session"
rg -Fq 'rememberStationConnectReconnectCredentials' "$client_manager"
