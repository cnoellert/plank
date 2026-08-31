#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
host_launcher=${repo_dir}/packaging/bin/stationconnect-host
client_launcher=${repo_dir}/packaging/bin/stationconnect-client
host_profile=${repo_dir}/packaging/config/stationconnect-host.conf
client_policy=${repo_dir}/packaging/config/stationconnect-client.conf
client_main=${repo_dir}/client/moonlight-qt-fork/app/main.cpp
client_path=${repo_dir}/client/moonlight-qt-fork/app/path.cpp

expect_status() {
  local expected=$1
  shift
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ ${actual} -ne ${expected} ]]; then
    echo "Expected status ${expected}, received ${actual}: $*" >&2
    return 1
  fi
}

expect_status 127 env STATIONCONNECT_HOST_BINARY=/does/not/exist \
  "${host_launcher}"
expect_status 1 env -u DISPLAY -u XAUTHORITY \
  STATIONCONNECT_HOST_BINARY=/bin/true "${host_launcher}"
expect_status 1 env DISPLAY=:99 XAUTHORITY=/does/not/exist \
  STATIONCONNECT_HOST_BINARY=/bin/true \
  STATIONCONNECT_AUTH_SOCKET=/does/not/exist "${host_launcher}"

expect_status 127 env STATIONCONNECT_CLIENT_BINARY=/does/not/exist \
  DISPLAY=:99 "${client_launcher}"
expect_status 1 env -u DISPLAY -u WAYLAND_DISPLAY \
  STATIONCONNECT_CLIENT_BINARY=/bin/true "${client_launcher}"
expect_status 0 env STATIONCONNECT_CLIENT_BINARY=/bin/true \
  DISPLAY=:99 "${client_launcher}" forwarded-argument

client_environment=$(env -u STATIONCONNECT_MDNS_DISCOVERY \
  STATIONCONNECT_CLIENT_BINARY=/usr/bin/env \
  STATIONCONNECT_CLIENT_LIBDIR="${repo_dir}/packaging" \
  XDG_CONFIG_HOME=/does/not/exist \
  LD_LIBRARY_PATH=/system/lib DISPLAY=:99 "${client_launcher}")
if ! grep -Fxq "LD_LIBRARY_PATH=${repo_dir}/packaging:/system/lib" \
  <<<"${client_environment}"; then
  echo 'Client launcher did not prefer the private library directory' >&2
  exit 1
fi
if grep -q '^STATIONCONNECT_MDNS_DISCOVERY=' <<<"${client_environment}"; then
  echo 'Client launcher injected a deprecated mDNS environment override' >&2
  exit 1
fi
if rg -n 'client\.env|source[[:space:]]+.*client_env' "${client_launcher}"; then
  echo 'Client launcher still loads user-controlled shell configuration' >&2
  exit 1
fi

client_config_root=$(mktemp -d)
trap 'rm -rf -- "${client_config_root}"' EXIT
mkdir -p "${client_config_root}/stationconnect"
printf '%s\n' 'STATIONCONNECT_MDNS_DISCOVERY=1' \
  >"${client_config_root}/stationconnect/client.env"
client_environment=$(env -u STATIONCONNECT_MDNS_DISCOVERY \
  XDG_CONFIG_HOME="${client_config_root}" \
  STATIONCONNECT_CLIENT_BINARY=/usr/bin/env \
  STATIONCONNECT_CLIENT_LIBDIR=/does/not/exist \
  DISPLAY=:99 "${client_launcher}")
if grep -q '^STATIONCONNECT_MDNS_DISCOVERY=' <<<"${client_environment}"; then
  echo 'Client launcher loaded the obsolete per-user client.env file' >&2
  exit 1
fi

grep -Fxq 'sw_vbv_maxrate_percentage = 150' "${host_profile}"
grep -Fxq 'sw_vbv_buffer_frames = 4' "${host_profile}"
grep -Fxq 'stationconnect_mdns_discovery = false' "${host_profile}"
grep -Fxq '# Listener address family: ipv4 = IPv4 only; both = IPv4 and IPv6.' \
  "${host_profile}"
grep -Fxq 'ping_timeout = 10000' "${host_profile}"
grep -Fxq 'fec_percentage = 20' "${host_profile}"
for section in network x264-encoder security discovery; do
  grep -Fxq "[${section}]" "${host_profile}"
done
if grep -Fxq '[software-encoder]' "${host_profile}"; then
  echo 'host profile contains the obsolete generic software-encoder section' >&2
  exit 1
fi
if rg -q '^\[video\]$|^[[:space:]]*(capture|encoder)[[:space:]]*=' "${host_profile}"; then
  echo 'host profile contains removed global video backend selectors' >&2
  exit 1
fi
if rg -q '^[[:space:]]*[A-Z][A-Z0-9_]*=' "${host_profile}"; then
  echo 'host profile contains shell environment syntax instead of INI syntax' >&2
  exit 1
fi
grep -Fxq '[network]' "${client_policy}"
grep -Fxq '# mdns_discovery = false' "${client_policy}"
grep -Fxq 'port = 28989' "${client_policy}"
if rg -q '^[[:space:]]*mdns_discovery[[:space:]]*=' "${client_policy}"; then
  echo 'Packaged client policy locks mDNS instead of leaving it user-configurable' >&2
  exit 1
fi

for required_log_token in XDG_STATE_HOME '.local/state' 'stationconnect/logs'; do
  rg -Fq "${required_log_token}" "${client_path}"
done
for required_log_token in \
  'stationconnect-client-*.log' \
  'MAX_LOG_SIZE_BYTES (10 * 1024 * 1024)' \
  'QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner' \
  'QFileDevice::ReadOwner | QFileDevice::WriteOwner' \
  's_LoggerFileStream << message' \
  '#if defined(Q_OS_LINUX) || !defined(LOG_TO_FILE)' \
  'Persistent client log:'; do
  rg -Fq "${required_log_token}" "${client_main}"
done
