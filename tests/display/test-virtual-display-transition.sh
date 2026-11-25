#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
test_build=$(mktemp -d)
trap 'rm -rf -- "$test_build"' EXIT
flags=(-O2)
if [[ ${PLANK_DISPLAY_SANITIZERS:-0} = 1 ]]; then
  flags=(-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined)
fi
"${CXX:-c++}" -std=c++20 "${flags[@]}" -Wall -Wextra -Wpedantic -Werror \
  -I"$repo_dir/apps/host/linux/src" \
  "$repo_dir/tests/display/virtual-display-transition.cpp" \
  -o "$test_build/virtual-display-transition"
"$test_build/virtual-display-transition"
