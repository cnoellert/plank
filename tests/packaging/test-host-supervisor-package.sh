#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
unit=${repo_dir}/packaging/systemd/stationconnect-host.service
pam_unit=${repo_dir}/packaging/systemd/stationconnect-pam-broker.service
spec=${repo_dir}/packaging/rpm/stationconnect-host.spec
builder=${repo_dir}/scripts/build-host-rpm.sh

rg -Fxq 'ExecStart=/usr/bin/stationconnect-host-supervisor' "$unit"
rg -Fxq 'WantedBy=multi-user.target' "$unit"
rg -Fxq 'EnvironmentFile=-/etc/stationconnect/host.env' "$unit"
rg -Fxq 'NoNewPrivileges=yes' "$unit"
rg -Fxq 'CapabilityBoundingSet=CAP_DAC_READ_SEARCH CAP_SYS_PTRACE' "$unit"
rg -Fxq 'ProtectHome=read-only' "$unit"
rg -Fxq 'RuntimeDirectory=stationconnect/host' "$unit"
rg -Fxq 'RuntimeDirectoryMode=0700' "$unit"
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
rg -Fq '/usr/lib/systemd/system/stationconnect-host.service' "$spec"
rg -Fq '/usr/lib/systemd/system-preset/90-stationconnect.preset' "$spec"
rg -Fq '%sysusers_create stationconnect.conf' "$spec"
rg -Fq 'stationconnect-host-certificate' "$spec"
rg -Fq 'stationconnect-host-state' "$spec"
rg -Fq '/var/lib/stationconnect/sunshine_state.json' "$spec"
rg -Fq 'file_state=/var/lib/stationconnect/sunshine_state.json' \
  "$repo_dir/packaging/bin/stationconnect-host"
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
rg -Fq 'restarting the StationConnect media worker for fresh X11/NvFBC state' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
rg -Fq 'stop_worker(worker);' \
  "$repo_dir/host/sunshine-fork/src/session/host_supervisor.cpp"
test "$(rg -F -c '!stationconnect_authentication && video::probe_encoders()' \
  "$repo_dir/host/sunshine-fork/src/nvhttp.cpp")" -eq 2

client_session="$repo_dir/client/moonlight-qt-fork/app/streaming/session.cpp"
client_manager="$repo_dir/client/moonlight-qt-fork/app/backend/computermanager.cpp"
client_input="$repo_dir/client/moonlight-qt-fork/app/streaming/input/input.cpp"
client_raw_wacom="$repo_dir/client/moonlight-qt-fork/app/streaming/input/linuxrawwacom.cpp"
rg -Fq 'StationConnect transport ended' "$client_session"
rg -Fq 'MaximumAttempts = 20' "$client_session"
rg -Fq 'replacement worker has no app to resume' "$client_session"
rg -Fq 'worker already has an active Desktop stream' "$client_session"
rg -Fq 'm_InputHandler->resetRawHidAfterReconnect();' "$client_session"
rg -Fq 'm_LinuxRawWacomInput->resetAfterReconnect();' "$client_input"
rg -Fq 'release(false);' "$client_raw_wacom"
rg -Fq 'm_AttachFailed.store(false);' "$client_raw_wacom"
rg -Fq 'm_CanReconnect.store(false)' "$client_session"
rg -Fq 'rememberStationConnectReconnectCredentials' "$client_manager"
