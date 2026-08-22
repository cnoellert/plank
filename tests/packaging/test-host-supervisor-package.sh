#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
unit=${repo_dir}/packaging/systemd/stationconnect-host.service
spec=${repo_dir}/packaging/rpm/stationconnect-host.spec
builder=${repo_dir}/scripts/build-host-rpm.sh

rg -Fxq 'ExecStart=/usr/bin/stationconnect-host-supervisor' "$unit"
rg -Fxq 'WantedBy=multi-user.target' "$unit"
rg -Fxq 'EnvironmentFile=-/etc/stationconnect/host.env' "$unit"
rg -Fxq 'NoNewPrivileges=yes' "$unit"
rg -q '^CapabilityBoundingSet=.*CAP_SETUID.*CAP_SETGID.*CAP_KILL' "$unit"
if rg -q '%h|graphical-session.target' "$unit"; then
  echo 'host unit still depends on a graphical user login' >&2
  exit 1
fi

rg -Fq '/usr/bin/stationconnect-host-supervisor' "$spec"
rg -Fq '/usr/lib/systemd/system/stationconnect-host.service' "$spec"
rg -Fq '/usr/lib/systemd/system-preset/90-stationconnect.preset' "$spec"
rg -Fq '%sysusers_create stationconnect.conf' "$spec"
rg -Fq 'stationconnect-host-certificate' "$spec"
if rg -Fq '/usr/lib/systemd/user/stationconnect-host.service' "$spec"; then
  echo 'RPM manifest still contains the obsolete host user unit' >&2
  exit 1
fi

rg -Fq 'refusing to package a dirty StationConnect source tree' "$builder"
rg -Fq 'stationconnect-host-supervisor' "$builder"
rg -Fq 'stationconnect-host-certificate' "$builder"
