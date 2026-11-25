#!/usr/bin/env bash
# Compile the production supervisor and exercise rollback without an X server.
set -euo pipefail
source /etc/os-release
[[ $ID = rocky && $VERSION_ID = 9.7 && $(uname -m) = x86_64 ]]
: "${PLANK_SOURCE_ROOT:?}" "${PLANK_WORK_ROOT:?}" "${PLANK_ARTIFACT_ROOT:?}"
root=$PLANK_SOURCE_ROOT
host="$root/apps/host/linux"
report="$PLANK_ARTIFACT_ROOT/qualification/display-transition"
build_dir="$PLANK_WORK_ROOT/cmake-build-display-transition"
mkdir -p "$report" "$build_dir"
git -C "$root" submodule update --init --depth 1 apps/host/linux
export CXX=/opt/rh/gcc-toolset-14/root/usr/bin/g++
bash "$root/tests/display/test-virtual-display-transition.sh" | tee "$report/normal.log"
PLANK_DISPLAY_SANITIZERS=1 bash "$root/tests/display/test-virtual-display-transition.sh" \
  | tee "$report/sanitizers.log"
"$CXX" -std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -pthread \
  "$host/src/session/host_supervisor.cpp" "$host/src/session/session_context.cpp" \
  -lsystemd -o "$build_dir/plank-host-supervisor" 2>&1 | tee "$report/compile.log"
# Never run the resulting supervisor on a builder.
sha256sum "$build_dir/plank-host-supervisor" | sed "s|$build_dir/||" > "$report/supervisor.sha256"
bash "$root/tests/display/test-display-prepare.sh" | tee "$report/prepare.log"
bash "$root/tests/packaging/test-host-supervisor-package.sh" | tee "$report/package-policy.log"
test -z "$(git -C "$root" status --porcelain)"
printf 'display_transition_component_gate=pass package_built=0 hardware_acceptance=not-performed\n'
