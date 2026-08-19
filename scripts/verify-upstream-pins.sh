#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

check_pin() {
  local path=$1
  local expected=$2
  local actual

  if [[ ! -e "$repo_root/$path/.git" ]]; then
    echo "$path: not initialized" >&2
    return 1
  fi

  actual=$(git -C "$repo_root/$path" rev-parse HEAD)
  if [[ "$actual" != "$expected" ]]; then
    echo "$path: expected $expected, found $actual" >&2
    return 1
  fi

  if ! git -C "$repo_root/$path" diff-index --quiet HEAD --; then
    echo "$path: tracked files are modified" >&2
    return 1
  fi

  echo "$path: $actual"
}

check_pin host/sunshine-fork 7bf3d2510d49748d191d7bc4c6b5bba38b9a0046
check_pin client/moonlight-qt-fork 71cf78468e0a956129e06ff8b127e89d0cd4b54a
check_pin \
  client/moonlight-qt-fork/moonlight-common-c/moonlight-common-c \
  a375aecb1dda17324ed58aee0d274d0c8e072c03

if git -C "$repo_root" submodule status --recursive | grep -q '^[+-]'; then
  echo "One or more nested submodules are not at their recorded commit" >&2
  exit 1
fi

echo "upstream_pins=pass"
