#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <canonical-host-repository> <candidate-host-repository>" >&2
  exit 2
fi

canonical_host=$(realpath "$1")
candidate_host=$(realpath "$2")

git -C "$canonical_host" rev-parse --is-inside-work-tree >/dev/null
git -C "$candidate_host" rev-parse --is-inside-work-tree >/dev/null

if [[ $(git -C "$canonical_host" rev-parse HEAD) != $(git -C "$candidate_host" rev-parse HEAD) ]]; then
  echo "Canonical and candidate host commits do not match" >&2
  exit 1
fi

init_level() {
  local canonical_parent=$1
  local candidate_parent=$2
  local key
  local path
  local name
  local -a paths=()

  if [[ ! -f "$candidate_parent/.gitmodules" ]]; then
    return
  fi

  while read -r key path; do
    name=${key#submodule.}
    name=${name%.path}

    if ! git -C "$canonical_parent/$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "Canonical submodule repository is unavailable: $canonical_parent/$path" >&2
      exit 1
    fi

    git -C "$candidate_parent" config "submodule.$name.url" "$canonical_parent/$path"
    paths+=("$path")
  done < <(git config -f "$candidate_parent/.gitmodules" --get-regexp '^submodule\..*\.path$')

  if [[ ${#paths[@]} -eq 0 ]]; then
    return
  fi

  git -c protocol.file.allow=always -C "$candidate_parent" \
    submodule update --init --checkout -- "${paths[@]}"

  for path in "${paths[@]}"; do
    init_level "$canonical_parent/$path" "$candidate_parent/$path"
  done
}

init_level "$canonical_host" "$candidate_host"

if git -C "$candidate_host" submodule status --recursive | grep -Eq '^[+-U]'; then
  echo "Candidate host has uninitialized or incorrect recursive submodules" >&2
  git -C "$candidate_host" submodule status --recursive >&2
  exit 1
fi

if [[ -n $(git -C "$candidate_host" status --porcelain) ]]; then
  echo "Candidate host is not clean after submodule initialization" >&2
  git -C "$candidate_host" status --short >&2
  exit 1
fi

echo "host_local_submodule_seed_gate=pass"
