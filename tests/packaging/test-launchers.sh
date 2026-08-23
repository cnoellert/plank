#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
host_launcher=${repo_dir}/packaging/bin/stationconnect-host
client_launcher=${repo_dir}/packaging/bin/stationconnect-client
host_profile=${repo_dir}/packaging/systemd/host.env.example

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

client_environment=$(env STATIONCONNECT_CLIENT_BINARY=/usr/bin/env \
  STATIONCONNECT_CLIENT_LIBDIR="${repo_dir}/packaging" \
  LD_LIBRARY_PATH=/system/lib DISPLAY=:99 "${client_launcher}")
if ! grep -Fxq "LD_LIBRARY_PATH=${repo_dir}/packaging:/system/lib" \
  <<<"${client_environment}"; then
  echo 'Client launcher did not prefer the private library directory' >&2
  exit 1
fi

grep -Eq '(^| )sw_vbv_maxrate_percentage=150( |$)' "${host_profile}"
grep -Eq '(^| )sw_vbv_buffer_frames=4( |$)' "${host_profile}"
