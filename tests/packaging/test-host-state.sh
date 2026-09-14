#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
helper=${repo_dir}/packaging/host/linux/bin/plank-host-state
test_dir=$(mktemp -d --tmpdir plank-host-state-test.XXXXXX)
cleanup() {
  rm -rf -- "$test_dir"
}
trap cleanup EXIT

state_file=${test_dir}/plank-state.json
"$helper" "$state_file"
if rg -q 'named_devices' "$state_file"; then
  echo 'state helper retained obsolete paired-device storage' >&2
  exit 1
fi
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
