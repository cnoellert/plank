#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
helper=${repo_dir}/packaging/bin/stationconnect-host-state
test_dir=$(mktemp -d --tmpdir stationconnect-host-state-test.XXXXXX)
cleanup() {
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

state_file=${test_dir}/sunshine_state.json
legacy_file=${test_dir}/legacy.json
legacy_uuid=1DE40C5B-53F1-E425-5493-2C5A6D9CC108

printf '{"root":{"uniqueid":"%s"}}\n' "$legacy_uuid" >"$legacy_file"
"$helper" "$state_file" "$legacy_file"
rg -Fq "\"uniqueid\": \"${legacy_uuid}\"" "$state_file"
[[ $(stat -c %a "$state_file") == 600 ]]

first_digest=$(sha256sum "$state_file")
"$helper" "$state_file"
[[ $(sha256sum "$state_file") == "$first_digest" ]]

printf '%s\n' 'invalid state' >"$state_file"
"$helper" "$state_file"
rg -q '"uniqueid": "[[:xdigit:]-]{36}"' "$state_file"

link_path=${test_dir}/state-link.json
ln -s "$state_file" "$link_path"
if "$helper" "$link_path" >/dev/null 2>&1; then
  echo 'state helper accepted a symlink target' >&2
  exit 1
fi

echo host_state_profile=pass
