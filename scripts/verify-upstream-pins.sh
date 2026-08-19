#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

check_baseline() {
  local path=$1
  local baseline=$2
  local actual

  if [[ ! -e "$repo_root/$path/.git" ]]; then
    echo "$path: not initialized" >&2
    return 1
  fi

  actual=$(git -C "$repo_root/$path" rev-parse HEAD)
  if ! git -C "$repo_root/$path" merge-base --is-ancestor "$baseline" "$actual"; then
    echo "$path: HEAD $actual does not descend from baseline $baseline" >&2
    return 1
  fi

  if ! git -C "$repo_root/$path" diff-index --quiet HEAD --; then
    echo "$path: tracked files are modified" >&2
    return 1
  fi

  echo "$path: baseline=$baseline head=$actual"
}

check_submodule_url() {
  local repository=$1
  local name=$2
  local expected=$3
  local actual

  actual=$(git -C "$repository" config --file .gitmodules --get "submodule.$name.url")
  if [[ "$actual" != "$expected" ]]; then
    echo "$repository: submodule $name expected URL $expected, found $actual" >&2
    return 1
  fi
}

check_baseline host/sunshine-fork 7bf3d2510d49748d191d7bc4c6b5bba38b9a0046
check_baseline client/moonlight-qt-fork 71cf78468e0a956129e06ff8b127e89d0cd4b54a
check_baseline \
  host/sunshine-fork/third-party/moonlight-common-c \
  d4e10b2f6ce197845101d0ac5089b0f5e77ccb72
check_baseline \
  client/moonlight-qt-fork/moonlight-common-c/moonlight-common-c \
  a375aecb1dda17324ed58aee0d274d0c8e072c03

check_submodule_url "$repo_root" host/sunshine-fork https://github.com/instinctual/plank-host-linux.git
check_submodule_url "$repo_root" client/moonlight-qt-fork https://github.com/instinctual/plank-client.git
check_submodule_url "$repo_root/host/sunshine-fork" third-party/moonlight-common-c https://github.com/instinctual/plank-common-c.git
check_submodule_url "$repo_root/client/moonlight-qt-fork" moonlight-common-c/moonlight-common-c https://github.com/instinctual/plank-common-c.git

if git -C "$repo_root" submodule status --recursive | grep -q '^[+-]'; then
  echo "One or more nested submodules are not at their recorded commit" >&2
  exit 1
fi

echo "upstream_baselines=pass"
